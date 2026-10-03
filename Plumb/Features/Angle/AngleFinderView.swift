//
//  AngleFinderView.swift
//  Plumb
//
//  Angle board: semicircle gauge 0–180°, absolute and relative (±90°) modes.
//

import SwiftUI

struct AngleFinderView: View {
    enum Mode: Hashable { case absolute, relative }

    private var motion = MotionService.shared
    @Environment(Router.self) private var router
    @Environment(\.colorScheme) private var scheme
    private var light: Bool { scheme == .light }

    @State private var mode: Mode = DebugLaunch.is("relative") ? .relative : .absolute
    /// Relative-mode zero, kept across launches so a reference survives leaving the screen.
    @AppStorage("angle.reference") private var reference: Double = 0
    @State private var lockedValue: Double?
    @State private var showInfo = false
    @State private var showToast = false

    var body: some View {
        let absolute = lockedValue ?? liveAbsolute
        let current = liveRelativeCurrent
        let delta = current - reference

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PMTopBar(title: "Angle Finder") {
                    IconCircleButton(icon: .info, label: "Measurement info", stroke: 1.8) {
                        withAnimation(PM.Motion.normal) { showInfo.toggle() }
                    }
                }

                PMSegmented(options: [(Mode.absolute, "ABSOLUTE"), (Mode.relative, "RELATIVE")], selection: $mode,
                            segmentHeight: light ? 44 : 40,
                            trackBorder: light ? .clear : PM.Colors.border,
                            fitContent: true, trackPadding: light ? 4 : 5)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                VStack(spacing: 4) {
                    Text(mode == .absolute ? toolChromeDegrees(absolute) : formatSignedDegrees(delta))
                        .font(.system(size: 72, weight: light ? .light : .thin))
                        .tracking(-2)
                        .monospacedDigit()
                        .foregroundStyle(isFlat ? PM.Colors.textTertiary : PM.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .cssLineBox(fontSize: 72, lineHeight: 1)
                        .contentTransition(.numericText())
                    Text(mode == .absolute ? "ANGLE" : "DELTA FROM REFERENCE")
                        .font(.pm(13, .heavy))
                        .tracking(light ? 1.4 : 1.6)
                        .foregroundStyle(PM.Colors.textSecondary)
                }
                .padding(.top, light ? 22 : 26)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(mode == .absolute ? "Angle from horizontal" : "Delta from reference")
                .accessibilityValue(mode == .absolute ? toolChromeDegrees(absolute) : formatSignedDegrees(delta))

                AngleGauge(mode: mode,
                           needle: mode == .absolute ? absolute : 90 + delta,
                           fillFrom: mode == .absolute ? 0 : 90)
                    .padding(.top, light ? 26 : 22)

                if mode == .relative {
                    HStack(spacing: 8) {
                        AngleValueCard(label: "REFERENCE", swatch: PM.Colors.calibrating, value: toolChromeDegrees(reference))
                        AngleValueCard(label: "CURRENT", swatch: PM.Colors.accent, value: toolChromeDegrees(current))
                        AngleValueCard(label: "DELTA", swatch: nil, value: formatSignedDegrees(delta))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                } else {
                    LivePill(text: isFlat ? "Stand iPhone on its long edge" : "Sensor · Device motion · from horizontal",
                             dot: isFlat ? PM.Colors.warning : PM.Colors.measuring)
                        .padding(.top, 16)
                    Text("Rest the long edge of your iPhone on the surface you want to measure.")
                        .font(.pm(light ? 14 : 13))
                        .lineSpacing((light ? 14 : 13) * 0.45 - 2.3)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, light ? 32 : 28)
                        .padding(.top, light ? 16 : 12)
                }

                Spacer(minLength: 0)
            }

            if showInfo {
                ToolChromeInfoPanel(rows: [
                    ("Sensor", "Device motion"),
                    ("Reference", mode == .absolute ? "Horizontal" : "Set reference"),
                    ("Stability", "\(Int((motion.stability * 100).rounded()))%"),
                    ("Display precision", "0.1°"),
                ])
                .padding(.horizontal, 12)
                .padding(.bottom, 66)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                if mode == .relative {
                    Button("Set Reference") {
                        reference = current
                        Haptics.measurementLocked()
                    }
                    .buttonStyle(.pmPrimary)
                    .disabled(isFlat)
                    .accessibilityHint("Makes the current angle the zero for relative readings")
                } else {
                    ToolChromeLockButton(locked: lockedValue != nil, disabled: isFlat && lockedValue == nil) {
                        if lockedValue != nil { lockedValue = nil }
                        else { lockedValue = liveAbsolute; Haptics.measurementLocked() }
                    }
                }
                Button { save(absolute: absolute, delta: delta) } label: {
                    Text("Save").fontWeight(light ? .bold : .semibold)
                }
                .buttonStyle(PMSecondaryButtonStyle(horizontalPadding: 22))
            }
            .padding(.horizontal, 20)
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .overlay { if lockedValue != nil && mode == .absolute { ToolChromeLockedFrame() } }
        .toolChromeToast($showToast)
        .animation(PM.Motion.normal, value: mode)
        .onAppear {
            if !motion.isAvailable && !DebugLaunch.isActive {
                // No motion sensor: show the honest unavailable state instead of numbers.
                if let i = router.path.lastIndex(of: .angle) { router.path[i] = .unavailable(.motionUnavailable) }
                return
            }
            motion.start()
        }
        .onDisappear { motion.stop() }
    }

    // Board values stand in when device motion is unavailable (Simulator, debug captures only).
    private var liveAbsolute: Double { motion.isAvailable ? sanitized(motion.edgeAngle) : 37.2 }
    private var liveRelativeCurrent: Double { motion.isAvailable ? sanitized(motion.edgeAngle) : 12.4 }

    /// Lying flat, gravity has no component in the screen plane and the edge angle is noise.
    private var isFlat: Bool { motion.isAvailable && lockedValue == nil && abs(motion.gravity.z) > 0.94 }

    private func sanitized(_ v: Double) -> Double { v.isFinite ? min(180, max(0, v)) : 0 }

    private func save(absolute: Double, delta: Double) {
        let isAbs = mode == .absolute
        MeasurementStore.shared.add(MeasurementRecord(
            name: isAbs ? "Angle" : "Relative angle",
            value: isAbs ? toolChromeDegrees(absolute) : formatSignedDegrees(delta),
            source: .sensor, tool: .angle, projectID: nil, date: Date()))
        withAnimation(PM.Motion.normal) { showToast = true }
    }
}

// MARK: - Gauge

/// 320 × 190 semicircle gauge. Angles run 0° (left) to 180° (right) around a pivot at (160, 170).
private struct AngleGauge: View {
    var mode: AngleFinderView.Mode
    var needle: Double
    var fillFrom: Double

    @Environment(\.colorScheme) private var scheme

    private static let pivot = CGPoint(x: 160, y: 170)
    private static let majorTick = Color(dark: 0x8A959B, light: 0x3A4247)
    private static let minorTick = Color(dark: 0x3A444B, light: 0x9AA39E)

    var body: some View {
        let clamped = min(180, max(0, needle))
        ZStack(alignment: .topLeading) {
            if scheme == .light {
                // Light mode: paper face with a steel rim.
                AngleHalfDisc(radius: 160)
                    .fill(RadialGradient(colors: [.white, Color(hex: 0xEEF0EC)], center: .bottom, startRadius: 0, endRadius: 160))
                    .overlay(AngleHalfDisc(radius: 157.5).stroke(Color(hex: 0xC3CAC5), lineWidth: 5))
                    .shadow(color: Color(hex: 0x0E1113).opacity(0.08), radius: 15, y: 12)
            }

            AngleSector(from: fillFrom, to: clamped, radius: 150, pivot: Self.pivot)
                .fill(PM.Colors.accent.opacity(0.16))

            if scheme != .light {
                AngleHalfDisc(radius: 149.5, pivot: Self.pivot, closed: false)
                    .stroke(PM.Colors.dialRim, lineWidth: 1)
            }

            Canvas { ctx, _ in
                let outer: CGFloat = scheme == .light ? 148 : 150
                for d in stride(from: 0, through: 180, by: 5) {
                    let major = d % 30 == 0
                    let len: CGFloat = major ? 14 : 7
                    let dir = Self.direction(Double(d))
                    var p = Path()
                    p.move(to: Self.point(dir, outer))
                    p.addLine(to: Self.point(dir, outer - len))
                    ctx.stroke(p, with: .color(major ? Self.majorTick : Self.minorTick), lineWidth: major ? 2 : 1)
                }
                var base = Path()
                if scheme == .light {
                    base.addRect(CGRect(x: 0, y: 169, width: 320, height: 2))
                    ctx.fill(base, with: .color(Color(hex: 0xC3CAC5)))
                } else {
                    base.addRect(CGRect(x: 10, y: 170, width: 300, height: 1))
                    ctx.fill(base, with: .color(PM.Colors.dialRim))
                }
            }

            ForEach(Array(stride(from: 0, through: 180, by: 30)), id: \.self) { d in
                let p = Self.point(Self.direction(Double(d)), 118)
                Text(label(d))
                    .font(.pmMono(11))
                    .foregroundStyle(PM.Colors.textSecondary)
                    .frame(width: 40)
                    .position(x: p.x, y: p.y - (scheme == .light && (d == 0 || d == 180) ? 12 : 0))
            }

            if mode == .relative {
                Rectangle()
                    .fill(PM.Colors.calibrating)
                    .frame(width: 2, height: 156)
                    .position(x: 160, y: 170 - 78)
            }

            // Needle: 2 × 148 from the pivot.
            let needleLength: CGFloat = scheme == .light ? 130 : 148
            Capsule()
                .fill(PM.Colors.accent)
                .frame(width: scheme == .light ? 3 : 2, height: needleLength)
                .shadow(color: scheme == .light ? .clear : PM.Colors.accent.opacity(0.6), radius: 6)
                .rotationEffect(.degrees(clamped - 90), anchor: .bottom)
                .position(x: 160, y: 170 - needleLength / 2)

            // Pivot: light dot ringed in the ground colour (dark), white ringed in ink (light).
            Circle()
                .fill(scheme == .light ? Color.white : PM.Colors.textPrimary)
                .overlay(Circle().strokeBorder(scheme == .light ? PM.Colors.textPrimary : PM.Colors.background, lineWidth: 3))
                .frame(width: 16, height: 16)
                .position(Self.pivot)
        }
        .frame(width: 320, height: 190)
        .animation(PM.Motion.spatial(0.2), value: needle)
        .accessibilityHidden(true)
    }

    private func label(_ d: Int) -> String {
        guard mode == .relative else { return "\(d)°" }
        let r = d - 90
        return (r > 0 ? "+" : "") + "\(r)°"
    }

    /// Unit vector for a gauge angle: 0° points left, 90° up, 180° right.
    static func direction(_ deg: Double) -> CGVector {
        let t = deg * .pi / 180
        return CGVector(dx: -cos(t), dy: -sin(t))
    }

    static func point(_ v: CGVector, _ r: CGFloat) -> CGPoint {
        CGPoint(x: pivot.x + v.dx * r, y: pivot.y + v.dy * r)
    }
}

/// Upper half of a circle around the pivot.
private struct AngleHalfDisc: Shape {
    var radius: CGFloat
    var pivot = CGPoint(x: 160, y: 170)
    var closed = true

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: pivot, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        if closed { p.closeSubpath() }
        return p
    }
}

/// Filled wedge between two gauge angles.
private struct AngleSector: Shape {
    var from: Double
    var to: Double
    var radius: CGFloat
    var pivot: CGPoint

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(from, to) }
        set { from = newValue.first; to = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: pivot)
        // Gauge angle g maps to screen angle 180° + g.
        p.addArc(center: pivot, radius: radius, startAngle: .degrees(180 + from), endAngle: .degrees(180 + to),
                 clockwise: to < from)
        p.closeSubpath()
        return p
    }
}

private struct AngleValueCard: View {
    var label: String
    var swatch: Color?
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let swatch { Rectangle().fill(swatch).frame(width: 8, height: 2) }
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.pm(12, .heavy))
            .tracking(swatch == nil ? 1 : 0.6)
            .foregroundStyle(swatch ?? PM.Colors.textSecondary)
            Text(value)
                .font(.pmMono(18))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .pmCard(radius: PM.Radius.cardSmall)
        .accessibilityElement(children: .combine)
    }
}
