//
//  Scenes.swift
//  Plumb
//
//  Hand-drawn scenes that stand in for camera and photo content, ported from the CSS on the boards.
//  Each scene fills the frame it is given; CSS percentages become fractions of that frame.
//  Hairline details (tile grout, 2 pt floor seams) stay in points, as they do in the CSS.
//

import SwiftUI

// MARK: - CSS helpers

/// CSS `linear-gradient(<deg>, ...)` for a box of `size`.
func cssLinearGradient(_ degrees: Double, _ stops: [Gradient.Stop], size: CGSize) -> LinearGradient {
    let a = CGFloat(degrees) * .pi / 180
    let dx = sin(a), dy = -cos(a)
    let w = max(size.width, 0.001), h = max(size.height, 0.001)
    // Gradient line length per the CSS spec.
    let len = abs(w * sin(a)) + abs(h * cos(a))
    let hx = dx * len / 2, hy = dy * len / 2
    let start = UnitPoint(x: 0.5 - hx / w, y: 0.5 - hy / h)
    let end = UnitPoint(x: 0.5 + hx / w, y: 0.5 + hy / h)
    return LinearGradient(stops: stops, startPoint: start, endPoint: end)
}

/// CSS `radial-gradient(ellipse RX RY at CX CY, ...)`. Radii and centre in points of the parent.
struct CSSRadialEllipse: View {
    var center: CGPoint
    var rx: CGFloat
    var ry: CGFloat
    var stops: [Gradient.Stop]

    var body: some View {
        Rectangle()
            .fill(EllipticalGradient(stops: stops, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
            .frame(width: rx * 2, height: ry * 2)
            .position(center)
            .allowsHitTesting(false)
    }
}

/// Rounded rectangle with CSS percentage radii: each corner is a fraction of width (x) and height (y).
struct CSSRoundedRect: Shape {
    var tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat

    init(_ all: CGFloat) { tl = all; tr = all; br = all; bl = all }
    init(tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat) { self.tl = tl; self.tr = tr; self.br = br; self.bl = bl }

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func rad(_ f: CGFloat) -> CGSize { CGSize(width: min(f, 0.5) * w, height: min(f, 0.5) * h) }
        let a = rad(tl), b = rad(tr), c = rad(br), d = rad(bl)
        let k: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: r.minX + a.width, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - b.width, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + b.height),
                   control1: CGPoint(x: r.maxX - b.width * (1 - k), y: r.minY),
                   control2: CGPoint(x: r.maxX, y: r.minY + b.height * (1 - k)))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c.height))
        p.addCurve(to: CGPoint(x: r.maxX - c.width, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.maxY - c.height * (1 - k)),
                   control2: CGPoint(x: r.maxX - c.width * (1 - k), y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + d.width, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - d.height),
                   control1: CGPoint(x: r.minX + d.width * (1 - k), y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.maxY - d.height * (1 - k)))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + a.height))
        p.addCurve(to: CGPoint(x: r.minX + a.width, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + a.height * (1 - k)),
                   control2: CGPoint(x: r.minX + a.width * (1 - k), y: r.minY))
        p.closeSubpath()
        return p
    }
}

extension View {
    /// Absolute placement like CSS `left/top/width/height`, inside a `ZStack(alignment: .topLeading)`.
    func sceneBox(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        frame(width: max(w, 0), height: max(h, 0)).offset(x: x, y: y)
    }

    /// CSS `filter: brightness(b) saturate(s)`. Brightness multiplies, unlike SwiftUI's additive `.brightness`.
    func sceneFilter(brightness: Double = 1, saturate: Double = 1) -> some View {
        saturation(saturate).colorMultiply(Color(white: brightness))
    }
}

/// Camera-feed darkening used over the scenes on AR, Room and States:
/// a radial vignette plus a 200 pt top gradient and a bottom gradient.
struct CameraVignette: View {
    var bottomHeight: CGFloat = 290

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                CSSRadialEllipse(center: CGPoint(x: g.size.width * 0.5, y: g.size.height * 0.48),
                                 rx: g.size.width * 0.95, ry: g.size.height * 0.80,
                                 stops: [.init(color: .black.opacity(0), location: 0),
                                         .init(color: .black.opacity(0), location: 0.55),
                                         .init(color: .black.opacity(0.42), location: 1)])
                LinearGradient(colors: [Color(hex: 0x060809, opacity: 0.72), Color(hex: 0x060809, opacity: 0)],
                               startPoint: .top, endPoint: .bottom)
                    .sceneBox(0, 0, g.size.width, 200)
                LinearGradient(colors: [Color(hex: 0x060809, opacity: 0), Color(hex: 0x060809, opacity: 0.78)],
                               startPoint: .top, endPoint: .bottom)
                    .sceneBox(0, g.size.height - bottomHeight, g.size.width, bottomHeight)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


// MARK: - iPad: never stretch a scene

/// On iPad (regular width) the scenes are laid out for much wider frames than the ~390 pt phone they were drawn
/// for. This draws the scene at its design size and scales it uniformly to cover the frame, cropping the
/// overflow, so proportions are kept. On iPhone it is a pass-through, so phone layouts are unchanged.
struct AdaptiveScene<Content: View>: View {
    var designWidth: CGFloat
    var designHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            GeometryReader { g in
                let k = max(g.size.width / designWidth, g.size.height / designHeight)
                content()
                    .frame(width: designWidth, height: designHeight)
                    .scaleEffect(k)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
                    .frame(width: g.size.width, height: g.size.height)
                    .clipped()
            }
        } else {
            content()
        }
    }
}

struct KitchenScene: View {
    var body: some View { AdaptiveScene(designWidth: 390, designHeight: 600) { KitchenSceneArt() } }
}

struct KitchenFloorScene: View {
    var body: some View { AdaptiveScene(designWidth: 390, designHeight: 284) { KitchenFloorSceneArt() } }
}

struct BenchScene: View {
    var body: some View { AdaptiveScene(designWidth: 325, designHeight: 200) { BenchSceneArt() } }
}

struct HallwayScene: View {
    var body: some View { AdaptiveScene(designWidth: 390, designHeight: 370) { HallwaySceneArt() } }
}

struct WallScene: View {
    var body: some View { AdaptiveScene(designWidth: 195, designHeight: 422) { WallSceneArt() } }
}

struct BathroomScene: View {
    var body: some View { AdaptiveScene(designWidth: 72, designHeight: 72) { BathroomSceneArt() } }
}

// MARK: - Kitchen

/// Kitchen, wide view: upper cabinets, splashback tiles, benchtop items, benchtop and lower cabinets.
/// Callers crop it the way each board does (e.g. Home: x −10%, y −22, 120% wide, 122 tall).
struct KitchenSceneArt: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(cssLinearGradient(100, [
                    .init(color: Color(hex: 0xE3DCCF), location: 0),
                    .init(color: Color(hex: 0xF0EBE2), location: 0.38),
                    .init(color: Color(hex: 0xDFD7CA), location: 1)], size: g.size))

                CSSRadialEllipse(center: CGPoint(x: w * 0.14, y: h * 0.18), rx: w * 0.6, ry: h * 0.7,
                                 stops: [.init(color: Color(hex: 0xFFF6DE, opacity: 0.8), location: 0),
                                         .init(color: Color(hex: 0xFFF6DE, opacity: 0), location: 0.7)])

                upperCabinets(w: w, h: h)

                LinearGradient(colors: [Color(red: 70/255, green: 58/255, blue: 40/255, opacity: 0.25),
                                        Color(red: 70/255, green: 58/255, blue: 40/255, opacity: 0)],
                               startPoint: .top, endPoint: .bottom)
                    .sceneBox(w * 0.03, h * 0.29, w * 0.94, h * 0.07)

                KitchenTiles().sceneBox(0, h * 0.29, w, h * 0.24)

                benchItems(w: w, h: h)

                // Benchtop surface in perspective.
                TrapezoidShape(inset: 0.025)
                    .fill(LinearGradient(colors: [Color(hex: 0xECE9E3), Color(hex: 0xD8D4CB)], startPoint: .top, endPoint: .bottom))
                    .sceneBox(0, h * 0.53, w, h * 0.05)

                // Benchtop front edge.
                LinearGradient(stops: [.init(color: Color(hex: 0xF6F4F0), location: 0),
                                       .init(color: Color(hex: 0xD0CBC1), location: 0.25),
                                       .init(color: Color(hex: 0xBBB5A9), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .sceneBox(0, h * 0.58, w, h * 0.045)

                KitchenLowerCabinets()
                    .sceneBox(w * 0.015, h * 0.625, w * 0.97, h * 0.325)

                LinearGradient(colors: [Color(red: 15/255, green: 17/255, blue: 15/255, opacity: 0.5),
                                        Color(red: 15/255, green: 17/255, blue: 15/255, opacity: 0)],
                               startPoint: .top, endPoint: .bottom)
                    .sceneBox(0, h * 0.625, w, h * 0.05)

                Color(hex: 0x252A27).sceneBox(0, h * 0.95, w, h * 0.05)
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func upperCabinets(w: CGFloat, h: CGFloat) -> some View {
        let rowW = w * 0.94
        let gap = rowW * 0.012
        let doorW = (rowW - gap * 3) / 4
        let doorH = h * 0.29
        return HStack(spacing: gap) {
            ForEach(0..<4, id: \.self) { _ in
                ZStack(alignment: .bottom) {
                    LinearGradient(colors: [Color(hex: 0xFBFAF6), Color(hex: 0xEAE7DF)], startPoint: .top, endPoint: .bottom)
                    // inset 0 -2px 0 rgba(0,0,0,0.04)
                    Color.black.opacity(0.04).frame(height: 2).padding(.horizontal, 1).padding(.bottom, 1)
                    // Handle: left/right 40%, bottom 9%, 3 tall.
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x8F8676))
                        .frame(width: max(doorW - 2, 0) * 0.2, height: 3)
                        .padding(.bottom, doorH * 0.09 + 1)
                }
                .overlay(OpenTopBorder().stroke(Color(hex: 0xD4CFC4), lineWidth: 1))
                .frame(width: max(doorW, 0), height: max(doorH, 0))
            }
        }
        .offset(x: w * 0.03)
    }

    private func benchItems(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Kettle
            CSSRoundedRect(tl: 0.34, tr: 0.34, br: 0.12, bl: 0.12)
                .fill(cssLinearGradient(90, [.init(color: Color(hex: 0x2C312F), location: 0),
                                             .init(color: Color(hex: 0x5A605D), location: 0.45),
                                             .init(color: Color(hex: 0x262A28), location: 1)],
                                        size: CGSize(width: w * 0.08, height: h * 0.12)))
                .shadow(color: .black.opacity(0.18), radius: 3, x: 3, y: 3)
                .sceneBox(w * 0.13, h * 0.41, w * 0.08, h * 0.12)
            // Kettle handle: 2 pt border without the right side (content box + border).
            OpenRightRounded(radiusFraction: 0.4)
                .stroke(Color(hex: 0x3A3F3D), lineWidth: 2)
                .sceneBox(w * 0.115 + 1, h * 0.435 + 1, w * 0.022 + 2, h * 0.04 + 2)
            // Glass
            CSSRoundedRect(0.18)
                .fill(LinearGradient(colors: [Color.white.opacity(0.6), Color(hex: 0xD6DCD8, opacity: 0.4)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(CSSRoundedRect(0.18).stroke(Color(hex: 0x78786E, opacity: 0.35), lineWidth: 1))
                .sceneBox(w * 0.25, h * 0.45, w * 0.045, h * 0.08)
            // Chopping board
            CSSRoundedRect(tl: 0.10, tr: 0.10, br: 0.04, bl: 0.04)
                .fill(cssLinearGradient(90, [.init(color: Color(hex: 0xB4865A), location: 0),
                                             .init(color: Color(hex: 0xD2A676), location: 0.5),
                                             .init(color: Color(hex: 0xAD7F4F), location: 1)],
                                        size: CGSize(width: w * 0.12, height: h * 0.17)))
                .shadow(color: .black.opacity(0.16), radius: 3.5, x: 3, y: 4)
                .sceneBox(w * 0.62, h * 0.36, w * 0.12, h * 0.17)
            // Pot
            CSSRoundedRect(tl: 0, tr: 0, br: 0.22, bl: 0.22)
                .fill(LinearGradient(colors: [Color(hex: 0xCFC8BB), Color(hex: 0xE4DED3)], startPoint: .leading, endPoint: .trailing))
                .sceneBox(w * 0.835, h * 0.46, w * 0.06, h * 0.07)
            // Plant: radial-gradient(circle at 40% 38%, ... 75%) with a farthest-corner radius.
            KitchenPlant().sceneBox(w * 0.815, h * 0.36, w * 0.10, h * 0.11)
        }
    }
}

private struct KitchenPlant: View {
    var body: some View {
        GeometryReader { g in
            let pw = g.size.width, ph = g.size.height
            let cx = pw * 0.4, cy = ph * 0.38
            let far = hypot(max(cx, pw - cx), max(cy, ph - cy))
            Ellipse().fill(RadialGradient(stops: [.init(color: Color(hex: 0x7FA878), location: 0),
                                                  .init(color: Color(hex: 0x3E6844), location: 0.75)],
                                          center: UnitPoint(x: 0.4, y: 0.38), startRadius: 0, endRadius: far))
        }
    }
}

/// 4 × 2 grid of lower cabinet doors with brass handles. Grid rows 30% / 1fr, gap 3, padding 2.
private struct KitchenLowerCabinets: View {
    var body: some View {
        GeometryReader { g in
            let pad: CGFloat = 2, gap: CGFloat = 3
            let cw = g.size.width - pad * 2, ch = g.size.height - pad * 2
            let colW = max((cw - gap * 3) / 4, 0)
            let row1 = max(ch * 0.30, 0)
            let row2 = max(ch - row1 - gap, 0)
            ZStack(alignment: .topLeading) {
                Color(hex: 0x2F3934)
                VStack(spacing: gap) {
                    row(colW: colW, rowH: row1, gap: gap, handleTop: 0.32)
                    row(colW: colW, rowH: row2, gap: gap, handleTop: 0.10)
                }
                .offset(x: pad, y: pad)
            }
        }
    }

    private func row(colW: CGFloat, rowH: CGFloat, gap: CGFloat, handleTop: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(0..<4, id: \.self) { _ in
                ZStack(alignment: .top) {
                    LinearGradient(colors: [Color(hex: 0x5E6E65), Color(hex: 0x4C5B53)], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 0) {
                        Color.white.opacity(0.08).frame(height: 1)
                        Spacer(minLength: 0)
                        Color.black.opacity(0.25).frame(height: 1)
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [Color(hex: 0xA98A52), Color(hex: 0xE2C992), Color(hex: 0xA98A52)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: colW * 0.28, height: 3)
                        .padding(.top, rowH * handleTop)
                }
                .frame(width: colW, height: rowH)
            }
        }
    }
}

/// Splashback tiles: 1 pt grout every 13 pt (rows) and 26 pt (columns).
private struct KitchenTiles: View {
    var body: some View {
        Canvas { ctx, size in
            var rows = Path()
            var y: CGFloat = 0
            while y < size.height { rows.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 13 }
            ctx.fill(rows, with: .color(Color(red: 120/255, green: 110/255, blue: 95/255, opacity: 0.12)))
            var cols = Path()
            var x: CGFloat = 0
            while x < size.width { cols.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 26 }
            ctx.fill(cols, with: .color(Color(red: 120/255, green: 110/255, blue: 95/255, opacity: 0.09)))
        }
    }
}

/// `clip-path: polygon(i 0, (1-i) 0, 100% 100%, 0 100%)`.
struct TrapezoidShape: Shape {
    var inset: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Left, right and bottom edges, inset half a point so a 1 pt stroke sits inside.
private struct OpenTopBorder: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 0.5, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + 0.5, y: r.maxY - 0.5))
        p.addLine(to: CGPoint(x: r.maxX - 0.5, y: r.maxY - 0.5))
        p.addLine(to: CGPoint(x: r.maxX - 0.5, y: r.minY))
        return p
    }
}

/// Rounded rectangle outline with the right edge missing (kettle handle).
private struct OpenRightRounded: Shape {
    var radiusFraction: CGFloat
    func path(in r: CGRect) -> Path {
        let rx = r.width * radiusFraction, ry = r.height * radiusFraction
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + rx, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + ry), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - ry))
        p.addQuadCurve(to: CGPoint(x: r.minX + rx, y: r.maxY), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

// MARK: - Floors

/// Perspective floor seams: rays from a vanishing point above the frame to evenly spaced points on the bottom
/// edge, plus optional horizontal seams. Ray ends are in 390-wide board units and scale with width.
private struct PerspectiveSeams: View {
    var vanishingYFraction: CGFloat
    var firstX: CGFloat
    var step: CGFloat
    var count: Int
    var rayColor: Color
    var horizontals: [CGFloat] = []

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 390
            let vp = CGPoint(x: size.width / 2, y: size.height * vanishingYFraction + 1)
            for (i, f) in horizontals.enumerated() {
                let rect = CGRect(x: 0, y: size.height * f, width: size.width, height: 2)
                ctx.fill(Path(rect), with: .color(Color(red: 70/255, green: 58/255, blue: 44/255,
                                                        opacity: 0.14 + Double(i) * 0.02)))
            }
            var rays = Path()
            for i in 0..<count {
                rays.move(to: vp)
                rays.addLine(to: CGPoint(x: (firstX + CGFloat(i) * step) * s, y: size.height + 1))
            }
            ctx.stroke(rays, with: .color(rayColor), lineWidth: 2)
        }
    }
}

/// Tiled kitchen floor seen from standing height (AR, Room, Report). Vanishing point sits 1.1 × height above.
struct KitchenFloorSceneArt: View {
    private static let seams: [CGFloat] = [0.3102, 0.4736, 0.5743, 0.6430, 0.6923, 0.7296, 0.7592,
                                           0.7827, 0.8021, 0.8183, 0.8320, 0.8437, 0.8539, 0.8630]

    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: [Color(hex: 0xADA290), Color(hex: 0xBFB4A3)], startPoint: .top, endPoint: .bottom)
                PerspectiveSeams(vanishingYFraction: -1.1, firstX: -585, step: 128, count: 13,
                                 rayColor: Color(red: 70/255, green: 58/255, blue: 44/255, opacity: 0.26),
                                 horizontals: Self.seams)
                LinearGradient(stops: [.init(color: Color(red: 25/255, green: 22/255, blue: 18/255, opacity: 0.4), location: 0),
                                       .init(color: Color(red: 25/255, green: 22/255, blue: 18/255, opacity: 0), location: 0.26),
                                       .init(color: Color.white.opacity(0.05), location: 0.8),
                                       .init(color: Color.black.opacity(0.15), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bench close-up

/// Close-up of the benchtop (Report, second photo): the kitchen cropped at (−100, −116, 520 × 286)
/// in a 325 × 200 frame, with the floor strip from y 170.
struct BenchSceneArt: View {
    var body: some View {
        GeometryReader { g in
            let sx = g.size.width / 325, sy = g.size.height / 200
            ZStack(alignment: .topLeading) {
                Color(hex: 0xEEF1EF)
                KitchenScene().sceneBox(-100 * sx, -116 * sy, 520 * sx, 286 * sy)
                KitchenFloorScene().sceneBox(0, 170 * sy, 325 * sx, 30 * sy)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Hallway

/// Hallway with a door, a framed picture and a timber floor (Photo Measure). Drawn on a 390 × 370 frame.
struct HallwaySceneArt: View {
    var body: some View {
        GeometryReader { g in
            let sx = g.size.width / 390, sy = g.size.height / 370
            ZStack(alignment: .topLeading) {
                Rectangle().fill(cssLinearGradient(90, [.init(color: Color(hex: 0xCBC3B6), location: 0),
                                                        .init(color: Color(hex: 0xDAD3C7), location: 0.45),
                                                        .init(color: Color(hex: 0xCFC7BA), location: 1)], size: g.size))
                // Ceiling and cornice
                LinearGradient(colors: [Color(hex: 0xEFEBE4), Color(hex: 0xE2DDD4)], startPoint: .top, endPoint: .bottom)
                    .sceneBox(0, 0, 390 * sx, 89 * sy)
                LinearGradient(colors: [Color(hex: 0xF6F3EE), Color(hex: 0xD6CFC3)], startPoint: .top, endPoint: .bottom)
                    .sceneBox(0, 86 * sy, 390 * sx, 6 * sy)
                // Ceiling light
                Capsule()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFFDF4), Color(hex: 0xE9E3D4)], center: .center,
                                         startRadius: 0, endRadius: 18 * sx))
                    .shadow(color: Color(hex: 0xFFF4D2, opacity: 0.7), radius: 12 * sx, y: 6 * sy)
                    .sceneBox(238 * sx, 30 * sy, 36 * sx, 10 * sy)
                CSSRadialEllipse(center: CGPoint(x: g.size.width * 0.64, y: g.size.height * 0.18),
                                 rx: g.size.width * 0.55, ry: g.size.height * 0.60,
                                 stops: [.init(color: Color(hex: 0xFFF7E2, opacity: 0.55), location: 0),
                                         .init(color: Color(hex: 0xFFF7E2, opacity: 0), location: 0.7)])
                // Door frame, leaf and panels
                LinearGradient(colors: [Color(hex: 0xF4F2ED), Color(hex: 0xE7E3DB)], startPoint: .leading, endPoint: .trailing)
                    .shadow(color: .black.opacity(0.12), radius: 2, x: 2)
                    .sceneBox(40 * sx, 134 * sy, 78 * sx, 166 * sy)
                LinearGradient(stops: [.init(color: Color(hex: 0xE8E3DA), location: 0),
                                       .init(color: Color(hex: 0xF1EDE6), location: 0.6),
                                       .init(color: Color(hex: 0xE2DDD3), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .overlay(Rectangle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                    .sceneBox(47 * sx, 141 * sy, 64 * sx, 159 * sy)
                HallwayDoorPanel().sceneBox(54 * sx, 150 * sy, 50 * sx, 62 * sy)
                HallwayDoorPanel().sceneBox(54 * sx, 222 * sy, 50 * sx, 70 * sy)
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x8E8A83))
                    .shadow(color: .black.opacity(0.3), radius: 0.5, y: 1)
                    .sceneBox(97 * sx, 214 * sy, 11 * sx, 3 * sy)
                // Light switch
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xF3F1EC))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                    .sceneBox(128 * sx, 196 * sy, 10 * sx, 16 * sy)
                // Framed picture: 4 pt mat around a 66 × 52 print (CSS content box plus border).
                HallwayPicture(sx: sx, sy: sy)
                    .sceneBox(218 * sx, 118 * sy, 74 * sx, 60 * sy)
                // Skirting board
                LinearGradient(colors: [Color(hex: 0xF7F5F1), Color(hex: 0xE6E1D8)], startPoint: .top, endPoint: .bottom)
                    .sceneBox(0, 286 * sy, 390 * sx, 14 * sy)
                Color.black.opacity(0.08).sceneBox(0, 285 * sy, 390 * sx, 1)
                // Timber floor
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x7E5F42), Color(hex: 0x9A7652)], startPoint: .top, endPoint: .bottom)
                    PerspectiveSeams(vanishingYFraction: -2.2, firstX: -585, step: 44, count: 36,
                                     rayColor: Color(red: 40/255, green: 25/255, blue: 12/255, opacity: 0.3))
                    LinearGradient(stops: [.init(color: Color(red: 20/255, green: 12/255, blue: 6/255, opacity: 0.35), location: 0),
                                           .init(color: Color(red: 20/255, green: 12/255, blue: 6/255, opacity: 0), location: 0.6)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .clipped()
                .sceneBox(0, 300 * sy, 390 * sx, 70 * sy)
                // Vignette
                CSSRadialEllipse(center: CGPoint(x: g.size.width * 0.5, y: g.size.height * 0.45),
                                 rx: g.size.width * 0.9, ry: g.size.height * 0.85,
                                 stops: [.init(color: .black.opacity(0), location: 0),
                                         .init(color: .black.opacity(0), location: 0.6),
                                         .init(color: .black.opacity(0.28), location: 1)])
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HallwayPicture: View {
    var sx: CGFloat
    var sy: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x3E4A47)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(colors: [Color(hex: 0x6F8A74), Color(hex: 0x4E6B58)],
                               startPoint: UnitPoint(x: 0.41, y: 0), endPoint: UnitPoint(x: 0.59, y: 1))
                    .frame(height: 52 * sy * 0.55)
            }
            Circle().fill(Color(hex: 0xE9D9A8))
                .frame(width: 9 * sx, height: 9 * sx)
                .offset(x: (66 - 12 - 9) * sx, y: 8 * sy)
        }
        .padding(.horizontal, 4 * sx)
        .padding(.vertical, 4 * sy)
        .background(Color(hex: 0xF2EFEA))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
    }
}

/// Recessed door panel: dark top-left and light bottom-right inset lines.
private struct HallwayDoorPanel: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Color.black.opacity(0.10).frame(height: 1)
                Spacer(minLength: 0)
                Color.white.opacity(0.7).frame(height: 1)
            }
            HStack(spacing: 0) {
                Color.black.opacity(0.10).frame(width: 1)
                Spacer(minLength: 0)
                Color.white.opacity(0.7).frame(width: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: - Wall

/// Plain painted wall with a light switch (States). Drawn on a 390 × 844 frame.
/// The States board dims it with `.sceneFilter(brightness: 0.72, saturate: 0.7)`.
struct WallSceneArt: View {
    var body: some View {
        GeometryReader { g in
            let sx = g.size.width / 390, sy = g.size.height / 844
            ZStack(alignment: .topLeading) {
                Rectangle().fill(cssLinearGradient(95, [.init(color: Color(hex: 0xC9CCCB), location: 0),
                                                        .init(color: Color(hex: 0xD9DBD9), location: 0.45),
                                                        .init(color: Color(hex: 0xCDD0CE), location: 1)], size: g.size))
                CSSRadialEllipse(center: CGPoint(x: g.size.width * 0.4, y: g.size.height * 0.35),
                                 rx: g.size.width * 0.7, ry: g.size.height * 0.55,
                                 stops: [.init(color: .white.opacity(0.35), location: 0),
                                         .init(color: .white.opacity(0), location: 0.7)])
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xE6E8E6))
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xF7F8F7))
                        .shadow(color: .black.opacity(0.2), radius: 0.5, y: 1)
                        .sceneBox(12 * sx, 18 * sy, 10 * sx, 18 * sy)
                }
                .sceneBox(250 * sx, 420 * sy, 34 * sx, 54 * sy)
                // repeating-linear-gradient(115deg, rgba(0,0,0,0.018) 0 2px, transparent 2px 7px)
                Canvas { ctx, size in
                    let a: CGFloat = 115 * .pi / 180
                    let dir = CGPoint(x: sin(a), y: -cos(a))
                    let perp = CGPoint(x: -dir.y, y: dir.x)
                    let diag = hypot(size.width, size.height)
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    var p = Path()
                    var t = -diag / 2
                    while t < diag / 2 {
                        let o = CGPoint(x: c.x + dir.x * (t + 1), y: c.y + dir.y * (t + 1))
                        p.move(to: CGPoint(x: o.x - perp.x * diag, y: o.y - perp.y * diag))
                        p.addLine(to: CGPoint(x: o.x + perp.x * diag, y: o.y + perp.y * diag))
                        t += 7
                    }
                    ctx.stroke(p, with: .color(.black.opacity(0.018)), lineWidth: 2)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bathroom

/// Bathroom tiles with a basin and tap (Projects thumbnail, drawn at 72 × 72).
struct BathroomSceneArt: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                Color(hex: 0xDDE3E2)
                Canvas { ctx, size in
                    var p = Path()
                    var y: CGFloat = 0
                    while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1.5)); y += 14 }
                    var x: CGFloat = 0
                    while x < size.width { p.addRect(CGRect(x: x, y: 0, width: 1.5, height: size.height)); x += 14 }
                    ctx.fill(p, with: .color(Color(red: 120/255, green: 135/255, blue: 135/255, opacity: 0.35)))
                }
                CSSRadialEllipse(center: CGPoint(x: w * 0.25, y: h * 0.20), rx: w * 0.7, ry: h * 0.7,
                                 stops: [.init(color: .white.opacity(0.6), location: 0),
                                         .init(color: .white.opacity(0), location: 0.7)])
                CSSRoundedRect(tl: 0.10, tr: 0.10, br: 0.45, bl: 0.45)
                    .fill(LinearGradient(colors: [.white, Color(hex: 0xE7ECEB)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 4)
                    .sceneBox(w * 0.34, h * 0.46, w * 0.44, h * 0.30)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(hex: 0x9AA3A3), Color(hex: 0xD6DBDB), Color(hex: 0x8E9797)],
                                         startPoint: .leading, endPoint: .trailing))
                    .sceneBox(w * 0.52, h * 0.30, w * 0.08, h * 0.18)
                LinearGradient(colors: [Color(hex: 0x8E9A99), Color(hex: 0x7A8685)], startPoint: .top, endPoint: .bottom)
                    .sceneBox(0, h * 0.80, w, h * 0.20)
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Scenes") {
    ScrollView {
        VStack(spacing: 12) {
            KitchenScene().frame(width: 390, height: 600)
            KitchenFloorScene().frame(width: 390, height: 284)
            BenchScene().frame(width: 325, height: 200)
            HallwayScene().frame(width: 390, height: 370)
            WallScene().frame(width: 195, height: 422)
            BathroomScene().frame(width: 72, height: 72)
        }
    }
    .background(Color.black)
}

// MARK: - CSS line boxes

extension View {
    /// Trims a single line of SF Pro to a CSS `line-height` (multiple of the font size), so text sits
    /// where the board puts it. SF Pro's natural line box is about 1.19 em.
    func cssLineBox(fontSize: CGFloat, lineHeight: CGFloat) -> some View {
        padding(.vertical, (lineHeight - 1.193) * fontSize / 2)
    }
}
