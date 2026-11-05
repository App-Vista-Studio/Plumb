//
//  ProtractorView.swift
//  Plumb
//
//  Protractor board: 0–180° dial with baseline and current needles.
//

import SwiftUI

struct ProtractorView: View {
    private var motion = MotionService.shared
    @Environment(Router.self) private var router

    /// Screen-plane angle (degrees) captured by "Set baseline". Persisted so it survives navigation.
    @AppStorage("protractor.baselineRaw") private var baselineRaw: Double = 0
    @State private var measuring = true
    @State private var frozen: Double?
    @State private var locked = false
    @State private var showInfo = false
    @State private var showToast = false

    var body: some View {
        let value = frozen ?? liveValue

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PMTopBar(title: "Protractor") {
                    IconCircleButton(icon: .info, label: "Measurement info", stroke: 1.8) {
                        withAnimation(PM.Motion.normal) { showInfo.toggle() }
                    }
                }

                VStack(spacing: 6) {
                    Text(toolChromeDegrees(value))
                        .font(.system(size: 80, weight: .thin))
                        .tracking(-2.4)
                        .monospacedDigit()
                        .foregroundStyle(isFlat ? PM.Colors.textTertiary : PM.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .cssLineBox(fontSize: 80, lineHeight: 1)
                        .contentTransition(.numericText())
                    if locked {
                        StatusPill(state: .aligned, text: "LOCKED", height: 26)
                    } else if isFlat {
                        LivePill(text: "Hold \(Device.name) upright to measure", dot: PM.Colors.warning)
                    } else {
                        LivePill(text: measuring ? "Measuring from baseline · Device motion" : "Paused · Tap Measure to resume",
                                 dot: measuring ? PM.Colors.measuring : PM.Colors.neutral)
                    }
                }
                .padding(.top, 30)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Angle from baseline")
                .accessibilityValue(toolChromeDegrees(value))

                // Dial + legend fill the space between the readout and the button grid:
                // the dial scales to the available width and the pair is centred vertically.
                GeometryReader { g in
                    let s = ProtractorDial.scale(for: g.size, reservedHeight: 40)
                    VStack(spacing: 16) {
                        ProtractorDial(angle: value)
                            .scaleEffect(s, anchor: .top)
                            .frame(width: ProtractorDial.size.width * s,
                                   height: ProtractorDial.size.height * s,
                                   alignment: .top)

                        HStack {
                            ProtractorLegend(color: PM.Colors.calibrating, text: "BASELINE 0.0°")
                            Spacer()
                            ProtractorLegend(color: PM.Colors.accent, text: "CURRENT \(toolChromeDegrees(value))")
                        }
                        .padding(.horizontal, 28)
                    }
                    .frame(width: g.size.width, height: g.size.height)
                }
                .padding(.top, 16)
                // Grid: two 54 pt rows + 10 pt gap, plus breathing room above it.
                .padding(.bottom, 118 + 20)
            }

            if showInfo {
                ToolChromeInfoPanel(rows: [
                    ("Sensor", "Device motion"),
                    ("Reference", "Baseline"),
                    ("Stability", "\(Int((motion.stability * 100).rounded()))%"),
                    ("Display precision", "0.1°"),
                ])
                .padding(.horizontal, 12)
                .padding(.bottom, 130)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Button("Set baseline") {
                        guard !isFlat else { return }
                        baselineRaw = rawAngle
                        frozen = nil
                        locked = false
                        measuring = true
                        Haptics.measurementLocked()
                    }
                    .buttonStyle(PMSecondaryButtonStyle(fillWidth: true))

                    Button("Measure") {
                        if measuring { frozen = liveValue } else { frozen = nil; locked = false }
                        measuring.toggle()
                    }
                    .buttonStyle(ProtractorToggleStyle(on: measuring))
                    .accessibilityAddTraits(measuring ? .isSelected : [])
                }
                GridRow {
                    Button {
                        if locked { locked = false; frozen = nil; measuring = true }
                        else { locked = true; frozen = value; Haptics.measurementLocked() }
                    } label: {
                        HStack(spacing: 8) {
                            PMIcon(.lock, size: 17, stroke: 2)
                            Text(locked ? "Unlock" : "Lock")
                        }
                    }
                    .buttonStyle(ProtractorLockStyle(locked: locked))

                    Button("Save") { save(value) }
                        .buttonStyle(PMSecondaryButtonStyle(fillWidth: true))
                }
            }
            .padding(.horizontal, 20)
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .overlay { if locked { ToolChromeLockedFrame() } }
        .toolChromeToast($showToast)
        .onAppear {
            if !motion.isAvailable && !DebugLaunch.isActive {
                if let i = router.path.lastIndex(of: .protractor) { router.path[i] = .unavailable(.motionUnavailable) }
                return
            }
            motion.start()
        }
        .onDisappear { motion.stop() }
    }

    /// Lying flat, the screen-plane rotation is undefined.
    private var isFlat: Bool { motion.isAvailable && frozen == nil && abs(motion.gravity.z) > 0.94 }

    /// Rotation in the screen plane: 0° with the phone upright.
    private var rawAngle: Double {
        let g = motion.gravity
        return atan2(g.x, -g.y) * 180 / .pi
    }

    private var liveValue: Double {
        guard motion.isAvailable else { return 64.0 } // board value for the Simulator
        let r = rawAngle - baselineRaw
        guard r.isFinite else { return 0 }
        var v = r.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v > 180 ? 360 - v : v
    }

    private func save(_ value: Double) {
        MeasurementStore.shared.add(MeasurementRecord(
            name: "Protractor angle", value: toolChromeDegrees(value),
            source: .sensor, tool: .protractor, projectID: nil, date: Date()))
        withAnimation(PM.Motion.normal) { showToast = true }
    }
}

// MARK: - Dial

/// 360 × 200 dial, pivot at (180, 180), radius 170. 0° is on the left.
private struct ProtractorDial: View {
    var angle: Double

    static let size = CGSize(width: 360, height: 200)
    private static let pivot = CGPoint(x: 180, y: 180)

    /// Scale that fits the dial into `available` (12 pt side inset), leaving `reservedHeight` for the legend.
    static func scale(for available: CGSize, reservedHeight: CGFloat) -> CGFloat {
        let byWidth = (available.width - 24) / size.width
        let byHeight = (available.height - reservedHeight) / size.height
        return max(0.5, min(byWidth, byHeight, 1.4))
    }
    private static let faceInner = Color(dark: 0x151C1F, light: 0xFFFFFF)
    private static let faceMid = Color(dark: 0x111518, light: 0xF6F5F1)
    private static let faceOuter = Color(dark: 0x0E1214, light: 0xEEF0EC)
    private static let faceEdge = Color(dark: 0x333C42, light: 0xC3CAC5)
    private static let tenTick = Color(dark: 0xC4CCD0, light: 0x2E353A)
    private static let fiveTick = Color(dark: 0x6E7A81, light: 0x545D63)
    private static let oneTick = Color(dark: 0x3A444B, light: 0xB9C0BB)

    var body: some View {
        let a = min(180, max(0, angle))
        ZStack(alignment: .topLeading) {
            ProtractorHalf(radius: 170, pivot: Self.pivot)
                .fill(RadialGradient(stops: [
                    .init(color: Self.faceInner, location: 0),
                    .init(color: Self.faceMid, location: 0.6),
                    .init(color: Self.faceOuter, location: 1),
                ], center: UnitPoint(x: 0.5, y: 0.9), startRadius: 0, endRadius: 240))
            ProtractorHalf(radius: 169.5, pivot: Self.pivot, closed: false)
                .stroke(Self.faceEdge, lineWidth: 1)

            ProtractorWedge(to: a, radius: 170, pivot: Self.pivot)
                .fill(PM.Colors.accent.opacity(0.18))

            Canvas { ctx, _ in
                for d in 0...180 {
                    let ten = d % 10 == 0, five = d % 5 == 0
                    let len: CGFloat = ten ? 16 : five ? 10 : 5
                    let t = Double(d) * .pi / 180
                    let v = CGVector(dx: -cos(t), dy: -sin(t))
                    var p = Path()
                    p.move(to: CGPoint(x: 180 + v.dx * 170, y: 180 + v.dy * 170))
                    p.addLine(to: CGPoint(x: 180 + v.dx * (170 - len), y: 180 + v.dy * (170 - len)))
                    ctx.stroke(p, with: .color(ten ? Self.tenTick : five ? Self.fiveTick : Self.oneTick), lineWidth: ten ? 2 : 1)
                }
            }

            ForEach(Array(stride(from: 0, through: 180, by: 10)), id: \.self) { d in
                let t = Double(d) * .pi / 180
                // 0 and 180 sit on the baseline: drop them just below it so the line doesn't strike through.
                let onBaseline = d == 0 || d == 180
                Text("\(d)")
                    .font(.pmMono(11))
                    .foregroundStyle(PM.Colors.textSecondary)
                    .frame(width: 28)
                    .position(x: onBaseline ? 180 - cos(t) * 160 : 180 - cos(t) * 138,
                              y: onBaseline ? 180 + 13 : 180 - sin(t) * 138)
            }

            // Baseline
            Rectangle().fill(PM.Colors.calibrating)
                .frame(width: 340, height: 2)
                .position(x: 180, y: 180)

            // Current needle: 2 × 168 from the pivot.
            Rectangle().fill(PM.Colors.accent)
                .frame(width: 2, height: 168)
                .shadow(color: PM.Colors.accent.opacity(0.6), radius: 6)
                .rotationEffect(.degrees(a - 90), anchor: .bottom)
                .position(x: 180, y: 180 - 84)

            Circle().fill(PM.Colors.textPrimary)
                .overlay(Circle().strokeBorder(PM.Colors.background, lineWidth: 4))
                .frame(width: 20, height: 20)
                .position(Self.pivot)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(PM.Motion.spatial(0.2), value: angle)
        .accessibilityHidden(true)
    }
}

private struct ProtractorHalf: Shape {
    var radius: CGFloat
    var pivot: CGPoint
    var closed = true

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: pivot, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        if closed { p.closeSubpath() }
        return p
    }
}

private struct ProtractorWedge: Shape {
    var to: Double
    var radius: CGFloat
    var pivot: CGPoint

    var animatableData: Double {
        get { to }
        set { to = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: pivot)
        p.addArc(center: pivot, radius: radius, startAngle: .degrees(180), endAngle: .degrees(180 + to), clockwise: false)
        p.closeSubpath()
        return p
    }
}

private struct ProtractorLegend: View {
    var color: Color
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 14, height: 2)
            Text(text).monospacedDigit()
        }
        .font(.pm(12, .bold))
        .tracking(1)
        .foregroundStyle(color)
    }
}

/// Measure: primary fill while measuring, secondary when paused.
private struct ProtractorToggleStyle: ButtonStyle {
    var on: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(16, on ? .bold : .semibold))
            .foregroundStyle(on ? PM.Colors.onAccent : PM.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(on ? PM.Colors.accent : PM.Colors.surfaceRaised))
            .overlay(Capsule().strokeBorder(on ? .clear : PM.Colors.borderStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Lock: secondary; accent outline once locked.
private struct ProtractorLockStyle: ButtonStyle {
    var locked: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(16, .semibold))
            .foregroundStyle(locked ? PM.Colors.accent : PM.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(locked ? PM.Colors.background : PM.Colors.surfaceRaised))
            .overlay(Capsule().strokeBorder(locked ? PM.Colors.accent : PM.Colors.borderStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
