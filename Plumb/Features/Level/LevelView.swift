//
//  LevelView.swift
//  Plumb
//
//  Bubble Level (Level + LevelStates boards): live, nearly, perfectly level, 3D and locked states.
//

import SwiftUI
import UIKit

struct LevelView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    private var motion = MotionService.shared
    private var settings = AppSettings.shared

    @State private var style: LevelInstrumentStyle = .classic
    @State private var locked: LevelLock?
    @State private var showInfo = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var hapticGate = LevelHapticGate()
    /// Upright on an edge rather than flat; switched with hysteresis so it never flickers.
    @State private var upright = false

    /// Debug review: `-state off|nearly|perfect|locked3d|plumb|edge|unavailable` renders a board phone or state.
    private let debugPhone = LevelDebugPhone(rawValue: DebugLaunch.state ?? "")
    /// LevelStates layout (hint line, 14 pt rhythm, no status row). The live board is the default.
    private var statesLayout: Bool { debugPhone != nil }

    init() {
        if let phone = LevelDebugPhone(rawValue: DebugLaunch.state ?? "") {
            _style = State(initialValue: phone == .locked3d ? .threeD : .classic)
            _locked = State(initialValue: phone == .locked3d
                            ? LevelLock(reading: LevelReading(mode: .flat, pitch: 0.1, roll: -0.2), at: phone.lockedAt) : nil)
        }
    }

    // MARK: Reading

    /// Live reading from the sensors: bubble level when flat, edge level when standing on an edge.
    private var liveReading: LevelReading {
        if let debugPhone { return debugPhone.reading }
        guard upright, !motion.isPreview else {
            return LevelReading(mode: .flat, pitch: motion.pitch, roll: motion.roll)
        }
        return LevelReading.edge(gravity: motion.gravity)
    }

    private var reading: LevelReading { locked?.reading ?? liveReading }
    private var pitch: Double { reading.pitch }
    private var roll: Double { reading.roll }
    private var magnitude: Double { reading.magnitude }
    private var status: LevelStatus {
        LevelStatus(magnitude: magnitude, perfect: settings.perfectTolerance, nearly: settings.nearlyTolerance)
    }
    private var isLocked: Bool { locked != nil }
    private var isEdge: Bool { reading.mode != .flat }

    private var bubbleOffset: CGSize {
        guard status != .perfect else { return .zero }
        return LevelInstrument.bubbleOffset(pitch: isEdge ? 0 : pitch, roll: roll)
    }

    private var rollDominant: Bool { isEdge || abs(roll) >= abs(pitch) }

    private var statusText: String {
        let word = reading.mode == .plumb ? "PLUMB" : "LEVEL"
        switch status {
        case .perfect: return "PERFECTLY " + word
        case .nearly: return "NEARLY " + word
        case .off:
            if rollDominant { return String(format: "%.1f° ", abs(roll)) + (roll > 0 ? "RIGHT" : "LEFT") }
            return String(format: "%.1f° ", abs(pitch)) + (pitch > 0 ? "UP" : "DOWN")
        }
    }

    private var arrowRotation: Double {
        if rollDominant { return roll > 0 ? 90 : -90 }
        return pitch > 0 ? 0 : 180
    }

    private var hintText: String {
        switch status {
        case .perfect: return String(format: "Within %.1f° tolerance", settings.perfectTolerance)
        case .nearly: return String(format: "Within %.1f° · keep adjusting", settings.nearlyTolerance)
        case .off:
            if reading.mode == .plumb { return roll > 0 ? "Tilt the top to the left" : "Tilt the top to the right" }
            // Lower the high side, where the bubble sits.
            if rollDominant { return roll > 0 ? "Lower the left side" : "Lower the right side" }
            return pitch > 0 ? "Lower the top edge" : "Lower the bottom edge"
        }
    }

    private var magText: String { String(format: "%.1f°", magnitude) }

    private var pillText: String {
        switch reading.mode {
        case .flat: "Sensor · Device motion"
        case .plumb: "Sensor · Edge mode · Plumb"
        case .edgeLevel: "Sensor · Edge mode · Level"
        }
    }

    private var calibrationText: String {
        // Simulator preview shows the board's text.
        if motion.isPreview { return "Calibrated · today" }
        guard let d = motion.calibratedAt else { return "Factory reference" }
        return Calendar.current.isDateInToday(d) ? "Calibrated · today" : "Calibrated · " + d.formatted(date: .abbreviated, time: .omitted)
    }

    private var sensorText: String {
        if motion.isPreview || motion.isRunning { return "Device motion · OK" }
        return motion.isSuspended ? "Device motion · paused" : "Device motion · starting"
    }

    private var unavailable: Bool {
        debugPhone == .unavailable || (!motion.isAvailable && !motion.isPreview)
    }

    // MARK: Body

    var body: some View {
        Group {
            if unavailable {
                UnavailableStateView(kind: .motionUnavailable)
            } else {
                GeometryReader { geo in
                    if geo.size.width > geo.size.height {
                        landscape
                    } else if colorScheme == .light {
                        lightPortrait
                    } else {
                        portrait
                    }
                }
            }
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .onChange(of: motion.gravity.z) { _, z in updateUpright(z) }
        .onChange(of: upright) { _, _ in hapticGate = LevelHapticGate() }
        .onChange(of: magnitude) { _, m in
            guard !isLocked, debugPhone == nil, !motion.isPreview else { return }
            hapticGate.update(magnitude: m, tolerance: settings.perfectTolerance)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { withAnimation(PM.Motion.normal) { showInfo = false } }
        }
    }

    private var portrait: some View {
        ZStack(alignment: .bottom) {
            PM.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                badgeRow
                    .frame(height: 26)
                    .padding(.top, 14)

                LevelInstrument(style: style, offset: bubbleOffset, isPerfect: status == .perfect,
                                showScaleLabels: !statesLayout && !isEdge)
                    .padding(.top, 18)

                readout.padding(.top, 18)

                controls.padding(.top, statesLayout ? 14 : 18)

                axisCards
                    .padding(.horizontal, 20)
                    .padding(.top, statesLayout ? 14 : 16)

                if !statesLayout {
                    statusRow
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }

                Spacer(minLength: 0)
            }

            overlays
        }
        .overlay { if isLocked { lockedGlow } }
    }

    /// LightMode board: larger utility dial, no style switch, status line beside a compact Lock button.
    private var lightPortrait: some View {
        ZStack(alignment: .bottom) {
            PM.Colors.background.ignoresSafeArea()

            VStack(spacing: 18) {
                PMTopBar(title: "Bubble Level", topPadding: 0, horizontalPadding: 0, leading: { BackButton() }) {
                    IconCircleButton(icon: .calibrate, label: "Calibrate") { router.push(.calibration) }
                }
                HStack { Spacer(); badgeRow; Spacer() }.frame(height: 26)

                VStack(spacing: 22) {
                    LevelInstrumentLight(offset: bubbleOffset, isPerfect: status == .perfect)
                    lightReadout
                }
                .frame(maxHeight: .infinity)

                axisCards

                HStack(spacing: 10) {
                    Button {
                        withAnimation(PM.Motion.normal) { showInfo.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            PMIcon(.check, size: 14, stroke: 2.4).foregroundStyle(PM.Colors.accent)
                            Text(lightStatusText)
                                .multilineTextAlignment(.leading)
                        }
                        .font(.pm(13))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lightStatusText)
                    .accessibilityHint("Shows measurement info")

                    Button { toggleLock() } label: {
                        HStack(spacing: 8) {
                            PMIcon(.lock, size: 16, stroke: 1.9)
                            Text(isLocked ? "Unlock" : "Lock")
                        }
                        .font(.pm(16, .bold))
                        .foregroundStyle(isLocked ? PM.Colors.accent : PM.Colors.onAccent)
                        .padding(.horizontal, 22)
                        .frame(height: 52)
                        .background(Capsule().fill(isLocked ? PM.Colors.surface : PM.Colors.accent))
                        .overlay(Capsule().strokeBorder(isLocked ? PM.Colors.accent : .clear, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pmPress)
                    .accessibilityHint(isLocked ? "Return to the live reading" : "Freeze the current reading")
                }
            }
            .padding(.top, 58 - PM.Board.statusBar)
            .padding(.horizontal, 20)
            .padding(.bottom, 34 - PM.Board.homeIndicator)

            if showInfo {
                LevelInfoPanel(stability: motion.isPreview ? 0.98 : motion.stability,
                               calibration: motion.calibratedAt, edge: isEdge)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 66)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(6)
            }
            if let toast {
                ToastView(text: toast).padding(.bottom, 74).zIndex(7)
            }
        }
        .overlay { if isLocked { lockedGlow } }
    }

    private var lightStatusText: String {
        let cal = motion.isPreview || motion.calibratedAt.map { Calendar.current.isDateInToday($0) } == true
            ? "Calibrated today" : (motion.calibratedAt == nil ? "Factory reference" : "Calibrated")
        let sensor = motion.isPreview || motion.stability >= 0.8 ? "Sensor good" : "Hold still"
        return isEdge ? "Edge mode · \(sensor)" : "\(cal) · \(sensor)"
    }

    private var lightReadout: some View {
        VStack(spacing: 8) {
            Text(magText)
                .font(.system(size: 64, weight: .light))
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(height: 64)
            HStack(spacing: 8) {
                switch status {
                case .perfect: PMIcon(.check, size: 16, stroke: 3)
                case .nearly: PMIcon(.nearly, size: 16, stroke: 2.2)
                case .off: PMIcon(.arrowUp, size: 16, stroke: 2.2).rotationEffect(.degrees(arrowRotation))
                }
                Text(statusText)
            }
            .font(.pm(14, .heavy))
            .tracking(1.2)
            .foregroundStyle(status == .perfect ? PM.Colors.onAccent : PM.Colors.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(status == .perfect ? PM.Colors.accent : PM.Colors.surface))
            .overlay(Capsule().strokeBorder(status == .perfect ? .clear : PM.Colors.border, lineWidth: 1))
            .animation(PM.Motion.levelSnap, value: status)
            if isLocked {
                lockedActions
            } else {
                Text(hintText)
                    .font(.pm(13))
                    .foregroundStyle(PM.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(magText), \(statusText.lowercased())")
    }

    /// Phone turned on its side with rotation unlocked: instrument left, readings right.
    private var landscape: some View {
        ZStack(alignment: .bottom) {
            PM.Colors.background.ignoresSafeArea()
            VStack(spacing: 8) {
                topBar
                HStack(spacing: 24) {
                    GeometryReader { g in
                        let scale = min(1, g.size.height / 280, g.size.width / 280)
                        LevelInstrument(style: style, offset: bubbleOffset, isPerfect: status == .perfect,
                                        showScaleLabels: !isEdge)
                            .scaleEffect(scale)
                            .frame(width: g.size.width, height: g.size.height)
                    }
                    VStack(spacing: 12) {
                        badgeRow.frame(height: 26)
                        readout
                        controls
                        axisCards
                        bottomBar
                    }
                    .frame(maxWidth: 360)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            if let toast {
                ToastView(text: toast).padding(.bottom, 20).zIndex(7)
            }
        }
        .overlay { if isLocked { lockedGlow } }
    }

    // MARK: Pieces

    private var topBar: some View {
        PMTopBar(title: "Bubble Level") {
            IconCircleButton(icon: .calibrate, label: "Calibrate") { router.push(.calibration) }
        }
    }

    @ViewBuilder private var overlays: some View {
        if showInfo {
            LevelInfoPanel(stability: motion.isPreview ? 0.98 : motion.stability,
                           calibration: motion.calibratedAt, edge: isEdge)
                .padding(.horizontal, 12)
                .padding(.bottom, 100 - PM.Board.homeIndicator)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(6)
        }

        bottomBar
            .padding(.horizontal, 20)

        if let toast {
            ToastView(text: toast)
                .padding(.bottom, 74)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(7)
        }
    }

    @ViewBuilder private var controls: some View {
        if isLocked {
            lockedActions
        } else {
            PMSegmented(options: [(LevelInstrumentStyle.classic, "CLASSIC"), (.threeD, "3D")],
                        selection: $style, fitContent: true, trackPadding: 5)
                .frame(width: 210)
        }
    }

    private var axisCards: some View {
        HStack(spacing: 10) {
            AxisReadout(label: isEdge ? "TILT" : "PITCH", value: formatSignedDegrees(isEdge ? roll : pitch))
            AxisReadout(label: isEdge ? "LEAN" : "ROLL", value: formatSignedDegrees(isEdge ? pitch : roll))
        }
    }

    private var statusRow: some View {
        HStack {
            checkLabel(isEdge ? "Edge mode · stand on the long edge" : calibrationText,
                       ok: isEdge || motion.calibratedAt != nil || motion.isPreview)
            Spacer()
            checkLabel(sensorText, ok: motion.isPreview || motion.isRunning)
        }
    }

    @ViewBuilder private var badgeRow: some View {
        if let locked {
            HStack(spacing: 6) {
                PMIcon(.lock, size: 12, stroke: 2.4)
                Text("LOCKED · " + locked.at.formatted(date: .omitted, time: .shortened).replacingOccurrences(of: "\u{202F}", with: " ").uppercased())
            }
            .font(.pm(12, .heavy))
            .tracking(0.8)
            .foregroundStyle(PM.Colors.onAccent)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(PM.Colors.accent))
            .accessibilityElement(children: .combine)
        } else {
            LivePill(text: pillText)
        }
    }

    private var readout: some View {
        VStack(spacing: 6) {
            Text(magText)
                .font(.system(size: 56, weight: .light))
                .tracking(-1.5)
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(height: 56)
                .contentTransition(.identity)

            HStack(spacing: 7) {
                switch status {
                case .perfect: PMIcon(.check, size: 15, stroke: 2.6)
                case .nearly: PMIcon(.nearly, size: 15, stroke: 2.2)
                case .off: PMIcon(.arrowUp, size: 15, stroke: 2.2).rotationEffect(.degrees(arrowRotation))
                }
                Text(statusText)
            }
            .font(.pm(13, .heavy))
            .tracking(1.2)
            .foregroundStyle(status == .perfect ? PM.Colors.onAccent : PM.Colors.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(status == .perfect ? PM.Colors.accent : PM.Colors.surfaceRaised))
            .animation(PM.Motion.levelSnap, value: status)

            if statesLayout || isEdge || isLocked {
                Text(hintText)
                    .font(.pm(13))
                    .foregroundStyle(PM.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(magText), \(statusText.lowercased())")
        .accessibilityHint(status == .perfect ? "" : hintText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var lockedActions: some View {
        HStack(spacing: 8) {
            Button("Save") { save() }.buttonStyle(LevelSmallButtonStyle())
            ShareLink(item: shareText) { Text("Share") }.buttonStyle(LevelSmallButtonStyle())
            Button("Copy") {
                UIPasteboard.general.string = shareText
                showToast("Copied")
            }
            .buttonStyle(LevelSmallButtonStyle())
        }
    }

    private func checkLabel(_ text: String, ok: Bool = true) -> some View {
        HStack(spacing: 6) {
            if ok {
                PMIcon(.check, size: 13, stroke: 2.4).foregroundStyle(PM.Colors.accent)
            } else {
                PMIcon(.info, size: 13, stroke: 2).foregroundStyle(PM.Colors.textTertiary)
            }
            Text(text)
        }
        .font(.pm(12))
        .foregroundStyle(PM.Colors.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if isLocked {
                Button { toggleLock() } label: {
                    HStack(spacing: 8) { PMIcon(.lock, size: 18, stroke: 2); Text("Unlock") }
                }
                .buttonStyle(.pmOutline)
                .accessibilityHint("Return to the live reading")
            } else {
                Button { toggleLock() } label: {
                    HStack(spacing: 8) { PMIcon(.lock, size: 18, stroke: 2); Text("Lock reading") }
                }
                .buttonStyle(.pmPrimary)
                .accessibilityHint("Freeze the current reading")
            }

            Button {
                withAnimation(PM.Motion.normal) { showInfo.toggle() }
            } label: {
                PMIcon(.info, size: 20, stroke: 1.8)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(PM.Colors.surfaceRaised))
                    .overlay(Circle().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.pmPress)
            .accessibilityLabel("Measurement info")
            .accessibilityValue(showInfo ? "Expanded" : "Collapsed")
        }
    }

    /// Glowing 2 pt border around the whole screen while a reading is locked (inset 0 0 28px glow).
    private var lockedGlow: some View {
        ToolChromeLockedFrame()
            .transition(.opacity)
    }

    // MARK: Actions

    private func updateUpright(_ z: Double) {
        guard debugPhone == nil, z.isFinite else { return }
        // Enter edge mode past ~57° from flat, leave below ~41°.
        let a = abs(z)
        if !upright, a < 0.55 { withAnimation(PM.Motion.normal) { upright = true } }
        else if upright, a > 0.75 { withAnimation(PM.Motion.normal) { upright = false } }
    }

    private var shareText: String {
        switch reading.mode {
        case .flat:
            "Level: \(magText) (pitch \(formatSignedDegrees(pitch)), roll \(formatSignedDegrees(roll))). Measured with Plumb."
        case .plumb:
            "Plumb: \(magText) \(roll > 0 ? "right" : "left") of vertical. Measured with Plumb."
        case .edgeLevel:
            "Edge level: \(magText) \(roll > 0 ? "right side low" : "left side low"). Measured with Plumb."
        }
    }

    private func toggleLock() {
        withAnimation(PM.Motion.normal) {
            if locked != nil {
                locked = nil
            } else {
                locked = LevelLock(reading: liveReading, at: Date())
                Haptics.measurementLocked()
            }
        }
    }

    private func save() {
        guard let locked else { return }
        let name = switch locked.reading.mode {
        case .flat: "Level"
        case .plumb: "Plumb"
        case .edgeLevel: "Edge level"
        }
        MeasurementStore.shared.add(MeasurementRecord(
            name: name, value: magText, source: .sensor, tool: .level, projectID: nil, date: locked.at))
        Haptics.measurementSaved()
        showToast("Measurement saved")
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(PM.Motion.normal) { toast = text }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(PM.Motion.normal) { toast = nil }
        }
    }
}

/// What the level is measuring.
enum LevelMode: Equatable {
    /// Lying flat: bubble level, pitch and roll.
    case flat
    /// Standing on the short edge (portrait upright): long edge against vertical.
    case plumb
    /// Standing on the long edge (landscape): long edge against horizontal.
    case edgeLevel
}

/// One level reading. In edge modes `roll` is the deviation of the edge (positive = clockwise as you
/// look at the screen, so the right side is low or the top leans right) and `pitch` is the lean of the screen.
struct LevelReading: Equatable {
    var mode: LevelMode
    var pitch: Double
    var roll: Double

    var magnitude: Double {
        let m = mode == .flat ? (pitch * pitch + roll * roll).squareRoot() : abs(roll)
        return m.isFinite ? m : 0
    }

    /// Edge reading from gravity in device coordinates: angle within the screen plane, snapped to the nearest
    /// quarter turn.
    static func edge(gravity g: SIMD3<Double>) -> LevelReading {
        let deg = 180.0 / .pi
        let theta = atan2(g.x, -g.y) * deg           // 0 upright portrait, +90 turned clockwise
        let quarter = (theta / 90).rounded()
        var d = theta - quarter * 90
        if !d.isFinite { d = 0 }
        let inPlane = (g.x * g.x + g.y * g.y).squareRoot()
        let lean = atan2(-g.z, inPlane) * deg        // screen tilted back from vertical
        let q = Int(quarter) & 3                     // 0 portrait, 1/3 landscape, 2 upside down
        return LevelReading(mode: q % 2 == 0 ? .plumb : .edgeLevel, pitch: lean.isFinite ? lean : 0, roll: d)
    }
}

/// LevelStates board phones, for design review.
private enum LevelDebugPhone: String {
    case off, nearly, perfect, locked3d, plumb, edge, unavailable

    var reading: LevelReading {
        switch self {
        case .off: LevelReading(mode: .flat, pitch: 0.3, roll: -2.4)
        case .nearly: LevelReading(mode: .flat, pitch: 0.4, roll: -0.5)
        case .perfect, .unavailable: LevelReading(mode: .flat, pitch: 0, roll: 0)
        case .locked3d: LevelReading(mode: .flat, pitch: 0.1, roll: -0.2)
        case .plumb: LevelReading(mode: .plumb, pitch: 2.1, roll: 1.6)
        case .edge: LevelReading(mode: .edgeLevel, pitch: -0.8, roll: -0.2)
        }
    }
    /// 10:42 AM today, as drawn.
    var lockedAt: Date {
        Calendar.current.date(bySettingHour: 10, minute: 42, second: 0, of: Date()) ?? Date()
    }
}

private struct LevelLock: Equatable {
    var reading: LevelReading
    var at: Date
}

/// Save / Share / Copy: 44 tall, raised fill, strong border, 14 semibold.
private struct LevelSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(14, .semibold))
            .foregroundStyle(PM.Colors.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Capsule().fill(PM.Colors.surfaceRaised))
            .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
    }
}

/// Measurement info dialog from the Level board.
private struct LevelInfoPanel: View {
    var stability: Double
    var calibration: Date?
    var edge = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("MEASUREMENT QUALITY").font(.pm(12, .heavy)).tracking(1.2).foregroundStyle(PM.Colors.textSecondary)
                Spacer()
                HStack(spacing: 6) {
                    if stability >= 0.8 {
                        PMIcon(.check, size: 14, stroke: 2.6)
                    } else {
                        SVGStroke(d: MeasureState.warning.iconPath, size: 14, lineWidth: 2.2)
                    }
                    Text(stability >= 0.8 ? "Good" : stability >= 0.5 ? "Fair · hold still" : "Moving")
                }
                .font(.pm(14, .bold))
                .foregroundStyle(stability >= 0.8 ? PM.Colors.accent : PM.Colors.warning)
            }
            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                row("Sensor", "Device motion")
                row("Reference", "Gravity")
                row("Stability", "\(Int((max(0, min(1, stability)) * 100).rounded()))%")
                row("Calibration", edge ? "Not used on edge" : calibrationText)
                row("Display precision", "0.1°")
            }
            .font(.pm(13))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(PM.Colors.surface.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: -10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Measurement info")
    }

    private var calibrationText: String {
        guard let calibration else { return "Factory reference" }
        return Calendar.current.isDateInToday(calibration) ? "Custom zero · today" : "Custom zero · " + calibration.formatted(date: .abbreviated, time: .omitted)
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(PM.Colors.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            Text(v).monospacedDigit().foregroundStyle(PM.Colors.textPrimary).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

#Preview {
    NavigationStack { LevelView() }
        .environment(Router())
}
