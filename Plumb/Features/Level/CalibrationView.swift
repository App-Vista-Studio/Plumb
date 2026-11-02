//
//  CalibrationView.swift
//  Plumb
//
//  Calibration (3 steps): wait for a stable surface, read the sensors, confirm the new zero.
//

import SwiftUI

struct CalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    private var motion = MotionService.shared

    /// Two-position (flip) calibration: a reading, a half turn on the same spot, a second reading.
    /// The average of the two cancels any slope in the surface, so only the phone's own offset is stored.
    enum Phase: String, Equatable {
        case place, firstRead, turn, secondRead, done
        case tooSteep, failed

        var step: Int {
            switch self {
            case .place, .tooSteep: 1
            case .firstRead, .turn, .secondRead, .failed: 2
            case .done: 3
            }
        }
    }

    @State private var phase: Phase
    /// Stability shown on the meter, 0...100.
    @State private var percent: Int
    @State private var offsetText = ""
    @State private var showManualTurn = false
    @State private var runID = 0

    /// Design review: `-state step1|step2|step3|turn|steep|failed` shows one state without running the flow.
    private let debugPhase: Phase?

    init() {
        let map: [String: (Phase, Int)] = ["step1": (.place, 34), "step2": (.firstRead, 98), "step3": (.done, 100),
                                           "turn": (.turn, 62), "steep": (.tooSteep, 96), "failed": (.failed, 90)]
        let fixture = DebugLaunch.state.flatMap { map[$0] }
        debugPhase = fixture?.0
        _phase = State(initialValue: fixture?.0 ?? .place)
        _percent = State(initialValue: fixture?.1 ?? 0)
    }

    private var step: Int { phase.step }

    var body: some View {
        if !motion.isAvailable && !motion.isPreview {
            UnavailableStateView(kind: .motionUnavailable)
        } else {
            content
        }
    }

    private var content: some View {
        GeometryReader { outer in
            VStack(spacing: 0) {
                // The scrolling area ends above the pinned disclaimer and action, so they never overlap.
                // It only scrolls if the content can't fit even with the illustration at its smallest.
                GeometryReader { g in
                    FitOrScroll {
                        steps(height: g.size.height)
                    }
                }

                bottomControls
                    .padding(.horizontal, 20)
                    // Home-button phones have no bottom inset; keep the button off the screen edge.
                    .padding(.bottom, outer.safeAreaInsets.bottom == 0 ? 16 : 0)
            }
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .task(id: runID) {
            guard debugPhase == nil else { return }
            await run()
        }
    }

    /// Heights of the content above and below the illustration, measured so the illustration
    /// takes whatever is left (board layout on 844 pt phones, scaled down on shorter ones).
    @State private var upperHeight: CGFloat = 137
    @State private var lowerHeight: CGFloat = 225

    /// Board illustration slot: 18 pt top padding + 260 pt frame. The art is drawn 24 pt up, so its
    /// last 24 pt are empty and the slot may shrink to 254 before the art has to scale.
    private static let boardSlot: CGFloat = 278
    private static let artExtent: CGFloat = 254

    private func steps(height h: CGFloat) -> some View {
        // 0 on the shortest phones (iPhone SE), 1 from the board height up: tightens the gaps.
        let t = min(1, max(0, (h - 510) / 110))
        let titleGap = 14 + 12 * t
        let cardGap = 14 + 8 * t
        let slot = min(Self.boardSlot, max(110, h - upperHeight - lowerHeight - 8))
        let k = min(1, slot / Self.artExtent)

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    Text("STEP \(step) OF 3")
                        .font(.pm(13, .bold)).tracking(1)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    HStack {
                        IconCircleButton(icon: .close, label: "Close", iconSize: 18, stroke: 2.2) { dismiss() }
                        Spacer()
                    }
                }
                .frame(height: 44)
                .padding(.top, 58 - PM.Board.statusBar)
                .padding(.horizontal, 16)

                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { i in
                        Capsule()
                            .fill(step >= i ? PM.Colors.accent : PM.Colors.tickMinor)
                            .frame(width: step >= i ? 24 : 6, height: 6)
                    }
                }
                .padding(.top, 14)
                .animation(PM.Motion.normal, value: step)
                .accessibilityHidden(true)

                Text("Calibrate Your Device")
                    .font(.pm(30, .bold)).tracking(-0.6)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, titleGap)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { upperHeight = $0 }

            // Board: 390 x 260 art, 18 pt below the title, drawn 24 pt up. Scaled from the top centre.
            CalibrationIllustration(phase: phase)
                .frame(width: 390, height: 260)
                .scaleEffect(k, anchor: .top)
                .offset(y: (18 - 24) * k)
                .frame(height: slot, alignment: .top)
                .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                // One copy block, updated in place (no crossfade between steps, which drew two steps'
                // text over each other). Hidden copies of every step reserve the tallest height so the
                // stability card doesn't move when the copy changes length.
                ZStack(alignment: .top) {
                    ForEach(Self.allPhases, id: \.self) { p in
                        copyBlock(copy(for: p))
                            .hidden()
                            .accessibilityHidden(true)
                    }
                    copyBlock(copy)
                        .accessibilityElement(children: .combine)
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .transaction(value: phase) { $0.animation = nil }

                stabilityCard
                    .padding(.horizontal, 20)
                    .padding(.top, cardGap)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lowerHeight = $0 }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            Text("Calibration adjusts the app's reference position. It can't make the sensors more accurate than your iPhone allows.")
                .font(.pm(12))
                .lineSpacing(12 * 0.45 - 2.4)
                .foregroundStyle(PM.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            Group {
                switch phase {
                case .done:
                    Button("Done") { dismiss() }
                        .buttonStyle(.pmPrimary)
                case .failed:
                    Button("Try again") { restart() }
                        .buttonStyle(.pmPrimary)
                case .turn where showManualTurn:
                    Button("I’ve turned it") { manualTurn = true }
                        .buttonStyle(PMSecondaryButtonStyle(fillWidth: true))
                default:
                    Text(waitingText)
                        .font(.pm(17, .bold))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(PM.Colors.surfaceRaised))
                        .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            // Swap the action instantly: a crossfade drew "Waiting for a stable surface" under "Calibrating…".
            .transaction(value: phase) { $0.animation = nil }
        }
    }

    @State private var manualTurn = false

    // MARK: Content

    private var waitingText: String {
        switch phase {
        case .place: "Waiting for a stable surface"
        case .tooSteep: "Waiting for a flatter surface"
        case .turn: "Waiting for a half turn"
        default: "Calibrating…"
        }
    }

    private static let allPhases: [Phase] = [.place, .tooSteep, .firstRead, .turn, .secondRead, .failed, .done]

    private func copyBlock(_ c: (title: String, body: String)) -> some View {
        VStack(spacing: 8) {
            BoardWrapText(c.title, size: 22, weight: .semibold, tracking: -0.3,
                          alignment: .center, color: PM.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            BoardWrapText(c.body, size: 15, lineHeight: 1.45, alignment: .center, color: PM.Colors.textSecondary)
        }
    }

    private var copy: (title: String, body: String) { copy(for: phase) }

    private func copy(for phase: Phase) -> (title: String, body: String) {
        switch phase {
        case .place: ("Place your iPhone on a stable surface.", "Use a flat table or floor. Take off a thick or uneven case if you can.")
        case .tooSteep: ("This surface is too steep.", "Calibration needs a surface within 5° of level. Try a table or the floor.")
        case .firstRead: ("Keep it still.", "Don’t touch the phone for a few seconds while we read the sensors.")
        case .turn: ("Now turn it around.", "Rotate your iPhone half a turn on the same spot, so the top points the other way. Then let go.")
        case .secondRead: ("Keep it still.", "One more reading in this position.")
        case .failed: ("The readings didn’t agree.", "Keep the phone in the same spot for both readings, on a surface that doesn’t move.")
        case .done: ("Calibration complete.", "This surface is now your zero reference. Recalibrate any time from the level screen." + offsetText)
        }
    }

    private var stateColor: Color {
        switch phase {
        case .place: PM.Colors.textSecondary
        case .firstRead, .turn, .secondRead: PM.Colors.calibrating
        case .tooSteep, .failed: PM.Colors.warning
        case .done: PM.Colors.accent
        }
    }

    private var stateText: String {
        switch phase {
        case .place: percent >= 90 ? "Steady" : "Moving"
        case .tooSteep: "Too steep"
        case .firstRead, .secondRead: "Calibrating"
        case .turn: "Turn 180°"
        case .failed: "Try again"
        case .done: "Complete"
        }
    }

    private var stabilityCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("STABILITY").font(.pm(12, .heavy)).tracking(1.2).foregroundStyle(PM.Colors.textSecondary)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    switch phase {
                    case .place: PMIcon(.pulse, size: 14, stroke: 2.2)
                    case .firstRead, .secondRead: PMIcon(.minus, size: 14, stroke: 2.2)
                    case .turn: SVGStroke(d: MeasureState.calibrating.iconPath, size: 14, lineWidth: 2.2)
                    case .tooSteep, .failed: SVGStroke(d: MeasureState.warning.iconPath, size: 14, lineWidth: 2.2)
                    case .done: PMIcon(.check, size: 14, stroke: 2.6)
                    }
                    Text(stateText)
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(.pm(13, .bold))
                .foregroundStyle(stateColor)
                // Status label swaps instantly; a crossfade left "Steady" showing behind the new label.
                .transaction(value: stateText) { $0.animation = nil }
            }
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i < Int((Double(percent) / 10).rounded()) ? stateColor : Color(dark: 0x262D33, light: 0xE2E5E1))
                            .frame(height: 14)
                    }
                }
                Text("\(percent)%")
                    .font(.pmMono(15))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .contentTransition(.identity)
                    .frame(width: 48, alignment: .trailing)
                    .fixedSize()
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .pmCard(radius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stability \(percent) percent, \(stateText)")
    }

    // MARK: Flow

    private func set(_ p: Phase) {
        guard p != phase else { return }
        withAnimation(PM.Motion.spatial()) { phase = p }
    }

    private func restart() {
        offsetText = ""
        showManualTurn = false
        manualTurn = false
        set(.place)
        runID += 1
    }

    private static let tick: Duration = .milliseconds(50)
    private static let maxSurfaceTilt = 5.0

    private func stable() -> Bool { motion.stability >= 0.9 && !motion.isSuspended }

    private func flatEnough() -> Bool {
        motion.isFlat && abs(motion.rawPitch) <= Self.maxSurfaceTilt + MotionService.maxZero
            && abs(motion.rawRoll) <= Self.maxSurfaceTilt + MotionService.maxZero
    }

    /// Steady for `seconds`, then returns. Reflects stability on the meter.
    private func waitUntilSteady(_ seconds: Double, require: () -> Bool = { true }) async -> Bool {
        var steadyFor = 0.0
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.tick)
            percent = Int((max(0, min(1, motion.stability)) * 100).rounded())
            steadyFor = stable() && require() ? steadyFor + 0.05 : 0
            if steadyFor >= seconds { return true }
        }
        return false
    }

    /// Averages raw pitch and roll for `seconds`. Returns nil if the phone moved.
    private func read(_ seconds: Double) async -> (pitch: Double, roll: Double)? {
        var sp = 0.0, sr = 0.0, n = 0.0
        let samples = Int(seconds / 0.05)
        for _ in 0..<samples {
            try? await Task.sleep(for: Self.tick)
            guard !Task.isCancelled else { return nil }
            percent = Int((max(0, min(1, motion.stability)) * 100).rounded())
            if motion.stability < 0.6 || motion.isSuspended || !motion.isFlat { return nil }
            sp += motion.rawPitch; sr += motion.rawRoll; n += 1
        }
        return n > 0 ? (sp / n, sr / n) : nil
    }

    private static func yawDelta(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return abs(d)
    }

    private func run() async {
        if motion.isPreview { await runPreview(); return }

        // 1. Stable and flat enough.
        var first: (pitch: Double, roll: Double)?
        while !Task.isCancelled && first == nil {
            set(.place)
            while !Task.isCancelled {
                guard await waitUntilSteady(1) else { return }
                if flatEnough() { break }
                set(.tooSteep)
            }
            // 2a. First reading.
            set(.firstRead)
            first = await read(2)
        }
        guard let first, !Task.isCancelled else { return }
        let yaw1 = motion.yaw

        // 2b. Half turn on the same spot, detected from the gyro heading.
        set(.turn)
        let turnStarted = Date()
        var second: (pitch: Double, roll: Double)?
        while !Task.isCancelled && second == nil {
            manualTurn = false
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                percent = Int((max(0, min(1, motion.stability)) * 100).rounded())
                if !showManualTurn, Date().timeIntervalSince(turnStarted) > 15 {
                    withAnimation(PM.Motion.normal) { showManualTurn = true }
                }
                let turned = abs(Self.yawDelta(motion.yaw, yaw1) - 180) <= 35 || manualTurn
                if turned && stable() && motion.isFlat { break }
            }
            guard await waitUntilSteady(0.6, require: { motion.isFlat }) else { return }
            set(.secondRead)
            second = await read(2)
            if second == nil { set(.turn) }
        }
        guard let second, !Task.isCancelled else { return }

        // 3. Average cancels the surface slope; what's left is the phone's own offset.
        let zp = (first.pitch + second.pitch) / 2
        let zr = (first.roll + second.roll) / 2
        guard abs(zp) <= MotionService.maxZero, abs(zr) <= MotionService.maxZero else {
            Haptics.selection()
            set(.failed)
            return
        }
        motion.applyCalibration(zeroPitch: zp, zeroRoll: zr)
        Haptics.calibrationComplete()
        offsetText = String(format: " Offset applied: pitch %@, roll %@.", formatSignedDegrees(-zp), formatSignedDegrees(-zr))
        withAnimation(PM.Motion.spatial()) {
            percent = 100
            phase = .done
        }
    }

    /// No sensor (Simulator, Debug only): walk through every step so the flow can be reviewed.
    private func runPreview() async {
        percent = 34
        for _ in 0..<16 {
            try? await Task.sleep(for: .milliseconds(100))
            percent = min(98, percent + 4)
        }
        for p in [Phase.firstRead, .turn, .secondRead] {
            guard !Task.isCancelled else { return }
            set(p)
            try? await Task.sleep(for: .seconds(1.5))
        }
        guard !Task.isCancelled else { return }
        withAnimation(PM.Motion.spatial()) {
            percent = 100
            phase = .done
        }
    }
}

// MARK: - Illustration

/// Table, tilted phone with a mini bubble, and the completion check. Board coordinates, 390 x 260.
private struct CalibrationIllustration: View {
    var phase: CalibrationView.Phase

    private var step: Int { phase.step }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Table: 320 x 90 at (35, 190), rotateX(62deg) from its bottom edge, perspective 900.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(dark: 0x1A2024, light: 0xE8EBE7), Color(dark: 0x111518, light: 0xDDE1DC)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(PM.Colors.border, lineWidth: 1))
                .frame(width: 320, height: 90)
                .levelCSSProjection(size: CGSize(width: 320, height: 90), origin: CGPoint(x: 160, y: 90),
                                    transforms: [.rotateX(62)],
                                    perspectiveOrigin: CGPoint(x: 195 - 35, y: 130 - 190), distance: 900)
                .offset(x: 35, y: 190)

            CalibrationPhone(miniBubbleX: step == 1 ? 10 : step == 2 ? 2 : 0)
                .rotationEffect(.degrees(phase == .turn || phase == .secondRead ? 180 : 0))
                .modifier(CalibrationPose(t: step == 1 ? 0 : 1))
                .offset(x: 150, y: 60)
                .animation(PM.Motion.spatial(0.9), value: phase)

            if phase == .turn {
                SVGStroke(d: MeasureState.calibrating.iconPath, size: 40, lineWidth: 2.2)
                    .foregroundStyle(PM.Colors.calibrating)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(Color(dark: 0x1E2236, light: 0xE9ECFB)))
                    .offset(x: 155, y: 20)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if step == 3 {
                PMIcon(.check, size: 40, stroke: 2.6)
                    .foregroundStyle(PM.Colors.onAccent)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(PM.Colors.accent))
                    .shadow(color: PM.Colors.accent.opacity(0.45), radius: 20)
                    .offset(x: 155, y: 20)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 390, height: 260, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private struct CalibrationPhone: View {
    var miniBubbleX: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(stops: [.init(color: Color(hex: 0x4A545A), location: 0),
                                         .init(color: Color(hex: 0x22282C), location: 0.6),
                                         .init(color: Color(hex: 0x5A646A), location: 1)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(hex: 0x0E1215))
                    .padding(6)
                    .overlay {
                        Circle().strokeBorder(Color(hex: 0x3A444B), lineWidth: 1)
                            .frame(width: 46, height: 46)
                            .overlay {
                                Circle().fill(PM.Colors.accent).frame(width: 14, height: 14)
                                    .offset(x: miniBubbleX)
                            }
                    }
            }
            .frame(width: 90, height: 180)
            .shadow(color: .black.opacity(0.55), radius: 25, y: 30)
    }
}

/// Interpolates between the board's two phone transforms over 700 ms:
/// step 1 `rotateX(28deg) rotateZ(-14deg) translateY(-10px)`, steps 2–3 `rotateX(62deg) translateY(70px)`.
private struct CalibrationPose: ViewModifier, Animatable {
    var t: Double

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        content.levelCSSProjection(
            size: CGSize(width: 90, height: 180), origin: CGPoint(x: 45, y: 90),
            transforms: [.rotateX(28 + 34 * t), .rotateZ(-14 * (1 - t)), .translateY(-10 + 80 * t)],
            // perspective origin: container centre (195, 130) minus phone origin (150, 60)
            perspectiveOrigin: CGPoint(x: 45, y: 70), distance: 900)
    }
}

#Preview {
    CalibrationView()
}
