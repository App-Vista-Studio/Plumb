//
//  SurfaceLevelView.swift
//  Plumb
//
//  Surface board: perspective plane, horizontal and vertical modes, lockable reading.
//

import SwiftUI

struct SurfaceLevelView: View {
    enum Mode: Hashable { case horizontal, vertical }

    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    private var motion = MotionService.shared

    @State private var mode: Mode = .horizontal
    @State private var locked: SurfaceLock?
    @State private var showInfo = false
    @State private var showToast = false

    var body: some View {
        let reading = currentReading
        let worst = max(abs(reading.pitch), abs(reading.roll))
        let isLevel = worst <= settings.perfectTolerance

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PMTopBar(title: "Surface Level") {
                    IconCircleButton(icon: .calibrate, label: "Calibrate") { router.push(.calibration) }
                }

                PMSegmented(options: [(Mode.horizontal, "HORIZONTAL"), (Mode.vertical, "VERTICAL")],
                            selection: $mode)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Group {
                    if let locked {
                        ToolChromeLockedPill(time: locked.at)
                    } else {
                        LivePill(text: "Sensor · Device motion")
                    }
                }
                .frame(height: 26)
                .padding(.top, 14)

                ZStack {
                    SurfacePlane(mode: mode, pitch: reading.pitch, roll: reading.roll)
                    SurfaceStatusPill(isLevel: isLevel, text: statusText(isLevel: isLevel, worst: worst))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .padding(.top, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(statusText(isLevel: isLevel, worst: worst))

                HStack(spacing: 10) {
                    SurfaceAxisCard(label: "PITCH", value: formatSignedDegrees(reading.pitch))
                    SurfaceAxisCard(label: "ROLL", value: formatSignedDegrees(reading.roll))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Text(mode == .horizontal ? "Lay your iPhone flat on the surface." : "Hold the long edge of your iPhone against the wall.")
                    .font(.pm(13))
                    .foregroundStyle(PM.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                if locked != nil {
                    ToolChromeLockedActions(shareText: shareText(reading), onSave: save)
                        .padding(.top, 14)
                }

                Spacer(minLength: 0)
            }

            if showInfo {
                ToolChromeInfoPanel(rows: [
                    ("Sensor", "Device motion"),
                    ("Reference", "Gravity"),
                    ("Stability", "\(Int((motion.stability * 100).rounded()))%"),
                    ("Calibration", motion.calibratedAt == nil ? "Factory" : "Custom zero"),
                    ("Display precision", "0.1°"),
                ])
                .padding(.horizontal, 12)
                .padding(.bottom, 66)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                ToolChromeLockButton(locked: locked != nil, lockLabel: "Lock Reading", action: toggleLock)
                ToolChromeInfoButton { withAnimation(PM.Motion.normal) { showInfo.toggle() } }
            }
            .padding(.horizontal, 20)
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .overlay { if locked != nil { ToolChromeLockedFrame() } }
        .toolChromeToast($showToast)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .onChange(of: mode) { _, _ in locked = nil }
    }

    // MARK: Values

    private var currentReading: (pitch: Double, roll: Double) {
        if let locked { return (locked.pitch, locked.roll) }
        guard motion.isAvailable else {
            // Board values, so the Simulator renders as designed.
            return mode == .horizontal ? (0.1, -0.1) : (1.3, -0.4)
        }
        switch mode {
        case .horizontal:
            return (motion.pitch, motion.roll)
        case .vertical:
            let g = motion.gravity
            let deg = 180.0 / .pi
            return (asin(max(-1, min(1, -g.z))) * deg, asin(max(-1, min(1, g.x))) * deg)
        }
    }

    private func statusText(isLevel: Bool, worst: Double) -> String {
        switch (mode, isLevel) {
        case (.horizontal, true): "LEVEL"
        case (.vertical, true): "PLUMB"
        case (.horizontal, false): String(format: "%.1f° OFF LEVEL", worst)
        case (.vertical, false): String(format: "%.1f° OUT OF PLUMB", worst)
        }
    }

    private func shareText(_ r: (pitch: Double, roll: Double)) -> String {
        "Surface \(mode == .horizontal ? "level" : "plumb"): pitch \(formatSignedDegrees(r.pitch)), roll \(formatSignedDegrees(r.roll)) (Plumb)"
    }

    private func toggleLock() {
        if locked != nil {
            locked = nil
        } else {
            let r = currentReading
            locked = SurfaceLock(pitch: r.pitch, roll: r.roll, at: Date())
            Haptics.measurementLocked()
        }
    }

    private func save() {
        let r = currentReading
        MeasurementStore.shared.add(MeasurementRecord(
            name: mode == .horizontal ? "Surface level" : "Wall plumb",
            value: toolChromeDegrees(max(abs(r.pitch), abs(r.roll))),
            source: .sensor, tool: .surface, projectID: nil, date: Date()))
        withAnimation(PM.Motion.normal) { showToast = true }
    }
}

private struct SurfaceLock {
    var pitch: Double
    var roll: Double
    var at: Date
}

// MARK: - Plane

private struct SurfacePlane: View {
    var mode: SurfaceLevelView.Mode
    var pitch: Double
    var roll: Double

    private static let fillTop = Color(dark: 0x18221F, light: 0xFFFFFF)
    private static let fillBottom = Color(dark: 0x0F1513, light: 0xEEF0EC)
    private static let edge = Color(dark: 0x2B4A3F, light: 0xC3CAC5)

    var body: some View {
        let size = mode == .horizontal ? CGSize(width: 250, height: 250) : CGSize(width: 200, height: 260)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        ZStack {
            // linear-gradient(160deg, …)
            shape.fill(LinearGradient(colors: [Self.fillTop, Self.fillBottom],
                                      startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97)))
            Canvas { ctx, s in
                var grid = Path()
                var x: CGFloat = 0
                while x <= s.width { grid.addRect(CGRect(x: x, y: 0, width: 1, height: s.height)); x += 26 }
                var y: CGFloat = 0
                while y <= s.height { grid.addRect(CGRect(x: 0, y: y, width: s.width, height: 1)); y += 26 }
                ctx.fill(grid, with: .color(PM.Colors.accent.opacity(0.12)))
                var axes = Path()
                axes.addRect(CGRect(x: s.width / 2, y: 0, width: 1, height: s.height))
                axes.addRect(CGRect(x: 0, y: s.height / 2, width: s.width, height: 1))
                ctx.fill(axes, with: .color(PM.Colors.accent.opacity(0.35)))
            }
            .clipShape(shape)
            shape.strokeBorder(Self.edge, lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.55), radius: 30, y: 30)
        // CSS perspective 800 px; SwiftUI's perspective is relative to the view's size.
        .modifier(SurfaceTilt(mode: mode, pitch: pitch, roll: roll, perspective: max(size.width, size.height) / 800))
        .animation(PM.Motion.spatial(0.25), value: mode)
        .animation(PM.Motion.bubbleSpring, value: pitch)
        .animation(PM.Motion.bubbleSpring, value: roll)
    }
}

private struct SurfaceTilt: ViewModifier {
    var mode: SurfaceLevelView.Mode
    var pitch: Double
    var roll: Double
    var perspective: CGFloat

    func body(content: Content) -> some View {
        switch mode {
        case .horizontal:
            // Board: rotateX(58deg) rotateY(0.3deg) at +0.1° / −0.1°.
            content
                .rotation3DEffect(.degrees(-roll * 3), axis: (x: 0, y: 1, z: 0), perspective: perspective)
                .rotation3DEffect(.degrees(58 + pitch), axis: (x: 1, y: 0, z: 0), perspective: perspective)
        case .vertical:
            // Board: rotateX(6deg) rotateZ(−1.3deg) at +1.3° out of plumb.
            content
                .rotationEffect(.degrees(-pitch))
                .rotation3DEffect(.degrees(6 + roll), axis: (x: 1, y: 0, z: 0), perspective: perspective)
        }
    }
}

private struct SurfaceStatusPill: View {
    var isLevel: Bool
    var text: String

    var body: some View {
        HStack(spacing: 7) {
            if isLevel {
                PMIcon(.check, size: 15, stroke: 2.6)
            } else {
                PMIcon(.arrowUp, size: 15, stroke: 2.2)
            }
            Text(text)
        }
        .font(.pm(14, .heavy))
        .tracking(1.2)
        .monospacedDigit()
        .foregroundStyle(isLevel ? PM.Colors.onAccent : PM.Colors.textPrimary)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Capsule().fill(isLevel ? PM.Colors.accent : PM.Colors.surfaceRaised))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
        .animation(PM.Motion.levelSnap, value: isLevel)
    }
}

private struct SurfaceAxisCard: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.pm(12, .heavy)).tracking(1.2).foregroundStyle(PM.Colors.textSecondary)
            Text(value)
                .font(.pm(36, .light))
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pmCard(radius: 20)
        .accessibilityElement(children: .combine)
    }
}
