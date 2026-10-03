//
//  LevelInstrument.swift
//  Plumb
//
//  Circular bubble level (Level and LevelStates boards). 280 pt dial drawn on the board's
//  own coordinate grid: 72 ticks, 140 and 60 rings, crosshair, dashed tolerance ring, bubble.
//

import SwiftUI

enum LevelInstrumentStyle: Hashable {
    case classic, threeD
}

struct LevelInstrument: View {
    var style: LevelInstrumentStyle = .classic
    /// Bubble offset from centre in points (board: dx = -roll * 10, dy = -pitch * 10, clamped to 100).
    var offset: CGSize = .zero
    var isPerfect = false
    /// "1°" and "5°" scale labels (live Level board).
    var showScaleLabels = true

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 280

    /// Bubble offset for a tilt so the rings read true: the 60 pt ring is 1°, the 140 pt ring is 5°.
    /// Piecewise linear (30 pt for the first degree, then 10 pt per degree), clamped at 100 pt (8°).
    /// The bubble moves to the high side, like a real vial.
    static func bubbleOffset(pitch: Double, roll: Double) -> CGSize {
        guard pitch.isFinite, roll.isFinite else { return .zero }
        let m = (pitch * pitch + roll * roll).squareRoot()
        guard m > 0 else { return .zero }
        let r = m <= 1 ? m * 30 : min(100, 30 + (m - 1) * 10)
        return CGSize(width: -roll / m * r, height: -pitch / m * r)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            face
            ticks
            ring(diameter: 140, at: 70, color: PM.Colors.dialLine)
            ring(diameter: 60, at: 110, color: Color(dark: 0x2E383F, light: 0xC9CFCB))
            Rectangle().fill(Color(dark: 0x232A30, light: 0xD6D9D4))
                .frame(width: 1, height: 228).offset(x: 139, y: 26)
            Rectangle().fill(Color(dark: 0x232A30, light: 0xD6D9D4))
                .frame(width: 228, height: 1).offset(x: 26, y: 139)

            if showScaleLabels {
                Text("5°").font(.pmMono(11)).foregroundStyle(PM.Colors.textTertiary)
                    .offset(x: 214, y: 124)
                Text("1°").font(.pmMono(11)).foregroundStyle(PM.Colors.textTertiary)
                    .offset(x: 172, y: 124)
            }

            if isPerfect { achieved }

            Circle()
                .strokeBorder(isPerfect ? PM.Colors.accent : Color(dark: 0x4A555C, light: 0xB9C0BB),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 48, height: 48)
                .offset(x: 116, y: 116)

            LevelBubble(style: style, isPerfect: isPerfect)
                .offset(x: 120 + offset.width, y: 120 + offset.height)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : PM.Motion.bubbleSpring, value: offset)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
        .onChange(of: isPerfect) { _, now in
            guard now, !reduceMotion else { return }
            // One ring, 420 ms, on entering tolerance.
            pulse = false
            withAnimation(.easeOut(duration: 0.42)) { pulse = true }
        }
    }

    // MARK: Face

    @ViewBuilder private var face: some View {
        switch style {
        case .classic:
            Circle()
                .fill(RadialGradient(
                    stops: [.init(color: PM.Colors.dialFaceTop, location: 0),
                            .init(color: PM.Colors.dialFaceBottom, location: 0.7)],
                    center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 223))
                .overlay(Circle().strokeBorder(PM.Colors.dialRim, lineWidth: 1))
                .overlay(
                    // inset 0 1px 0 rgba(255,255,255,0.08)
                    Circle().inset(by: 1).strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 25, y: 20)
                .frame(width: size, height: size)
        case .threeD:
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(AngularGradient(
                        colors: [Color(hex: 0x8A949A), Color(hex: 0x2E353A), Color(hex: 0xC9D1D5), Color(hex: 0x3A4248),
                                 Color(hex: 0x9AA4AA), Color(hex: 0x2E353A), Color(hex: 0x8A949A)],
                        center: .center, startAngle: .degrees(-70), endAngle: .degrees(290)))
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 24)
                    .frame(width: size, height: size)
                Circle()
                    .fill(RadialGradient(
                        stops: [.init(color: Color(hex: 0x16302A), location: 0),
                                .init(color: Color(hex: 0x0D1714), location: 0.62),
                                .init(color: Color(hex: 0x070B0A), location: 1)],
                        center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 190))
                    .overlay(
                        // inset 0 6px 18px rgba(0,0,0,0.7)
                        Circle().stroke(Color.black.opacity(0.7), lineWidth: 18)
                            .blur(radius: 9).offset(y: 6).mask(Circle())
                    )
                    .frame(width: 262, height: 262)
                    .offset(x: 9, y: 9)
                Ellipse()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 35))
                    .scaleEffect(x: 75 / 35, y: 1)
                    .frame(width: 150, height: 70)
                    .rotationEffect(.degrees(-18))
                    .offset(x: 50, y: 22)
            }
        }
    }

    private var ticks: some View {
        let top: CGFloat = style == .threeD ? 12 : 4
        return Canvas { ctx, _ in
            let c = CGPoint(x: 140, y: 140)
            for i in 0..<72 {
                let major = i % 6 == 0
                let w: CGFloat = major ? 2 : 1
                let h: CGFloat = major ? 12 : 6
                var t = ctx
                t.translateBy(x: c.x, y: c.y)
                t.rotate(by: .degrees(Double(i) * 5))
                t.fill(Path(CGRect(x: -w / 2, y: top - 140, width: w, height: h)),
                       with: .color(major ? PM.Colors.tickMajor : PM.Colors.tickMinor))
            }
        }
        .frame(width: size, height: size)
    }

    private func ring(diameter: CGFloat, at: CGFloat, color: Color) -> some View {
        Circle().strokeBorder(color, lineWidth: 1)
            .frame(width: diameter, height: diameter)
            .offset(x: at, y: at)
    }

    /// Radial glow, 92 pt halo and a single pulse ring (LevelStates phone 3).
    private var achieved: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(RadialGradient(colors: [PM.Colors.accent.opacity(0.30), PM.Colors.accent.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 80))
                .frame(width: 160, height: 160)
                .offset(x: 60, y: 60)
            Circle().strokeBorder(PM.Colors.accent.opacity(0.45), lineWidth: 1)
                .frame(width: 92, height: 92)
                .offset(x: 94, y: 94)
            Circle().strokeBorder(PM.Colors.accent, lineWidth: 1)
                .frame(width: 48, height: 48)
                .scaleEffect(pulse ? 1.6 : 1)
                .opacity(pulse ? 0 : 0.6)
                .offset(x: 116, y: 116)
        }
        .transition(.opacity.animation(PM.Motion.levelSnap))
    }
}

/// 40 pt bubble with the board's radial highlight and glow.
struct LevelBubble: View {
    var style: LevelInstrumentStyle
    var isPerfect: Bool
    var diameter: CGFloat = 40

    var body: some View {
        Circle()
            .fill(fill)
            .overlay {
                if style == .threeD {
                    // inset 0 -3px 6px rgba(0,0,0,0.25)
                    Circle().stroke(Color.black.opacity(0.25), lineWidth: 6)
                        .blur(radius: 3).offset(y: -3).mask(Circle())
                }
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: PM.Colors.accent.opacity(isPerfect ? 0.6 : 0.35), radius: isPerfect ? 14 : 8)
    }

    private var fill: RadialGradient {
        let centre = UnitPoint(x: style == .threeD ? 0.34 : 0.35, y: style == .threeD ? 0.28 : 0.30)
        // farthest-corner radius from the highlight point
        let r = diameter * 0.96
        switch style {
        case .classic:
            return RadialGradient(stops: [.init(color: .white, location: 0),
                                          .init(color: PM.Colors.accent, location: 0.38),
                                          .init(color: PM.Colors.accentDeep, location: 1)],
                                  center: centre, startRadius: 0, endRadius: r)
        case .threeD:
            return RadialGradient(stops: [.init(color: .white.opacity(0.95), location: 0),
                                          .init(color: Color(red: 190 / 255, green: 1, blue: 230 / 255).opacity(0.55), location: 0.30),
                                          .init(color: Color(hex: 0x52F2B8, opacity: 0.35), location: 0.70),
                                          .init(color: Color(hex: 0x52F2B8, opacity: 0.15), location: 1)],
                                  center: centre, startRadius: 0, endRadius: r)
        }
    }
}

#Preview {
    HStack {
        LevelInstrument(style: .classic, offset: CGSize(width: -12, height: 4))
        LevelInstrument(style: .threeD, isPerfect: true, showScaleLabels: false)
    }
    .padding()
    .background(PM.Colors.background)
}

/// Light-theme bubble level from the LightMode board: 290 pt, 6 pt rim, 36 ticks, two rings, 36 pt bubble.
struct LevelInstrumentLight: View {
    var offset: CGSize = .zero
    var isPerfect = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Children sit inside the 6 pt border (CSS padding box), so board coordinates are offset by 6.
        let b: CGFloat = 6
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: Color(hex: 0xECEFEA), location: 0.8)],
                                     center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 270))
                .overlay(Circle().inset(by: b).stroke(Color.white, lineWidth: 1).offset(y: 1).clipShape(Circle().inset(by: b)))
                .overlay(Circle().strokeBorder(Color(hex: 0xC3CAC5), lineWidth: b))
                .shadow(color: Color(hex: 0x0E1113, opacity: 0.12), radius: 20, y: 18)
                .frame(width: 290, height: 290)
            Canvas { ctx, _ in
                for i in 0..<36 {
                    let major = i % 9 == 0
                    var t = ctx
                    t.translateBy(x: b + 138, y: b + 139)
                    t.rotate(by: .degrees(Double(i) * 10))
                    t.fill(Path(CGRect(x: 0, y: -133, width: major ? 2 : 1, height: major ? 14 : 7)),
                           with: .color(Color(hex: major ? 0x3A4247 : 0x9AA39E)))
                }
            }
            .frame(width: 290, height: 290)
            Rectangle().fill(Color(hex: 0xD2D8D3)).frame(width: 1, height: 222).offset(x: b + 138, y: b + 28)
            Rectangle().fill(Color(hex: 0xD2D8D3)).frame(width: 222, height: 1).offset(x: b + 28, y: b + 138)
            Circle().strokeBorder(Color(hex: 0x007A55, opacity: 0.35), lineWidth: 1)
                .frame(width: 80, height: 80).offset(x: b + 99, y: b + 99)
            Circle().strokeBorder(isPerfect ? Color(hex: 0x007A55) : Color(hex: 0x9AA39E), lineWidth: 2)
                .frame(width: 50, height: 50).offset(x: b + 113, y: b + 113)
            Circle()
                .fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: Color(hex: 0x1FA877), location: 0.45),
                                             .init(color: Color(hex: 0x007A55), location: 1)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 34))
                .frame(width: 36, height: 36)
                .shadow(color: Color(hex: 0x007A55, opacity: 0.35), radius: 6, y: 4)
                .offset(x: b + 120 + offset.width, y: b + 120 + offset.height)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : PM.Motion.bubbleSpring, value: offset)
        }
        .frame(width: 290, height: 290, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
