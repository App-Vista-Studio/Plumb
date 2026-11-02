//
//  ShapeDiagram.swift
//  Plumb
//
//  Vector diagrams for the Shape Area calculators. The outline follows the entered proportions
//  (clamped so thin or extreme shapes stay readable) and springs between values.
//  Each shape always draws the same number of points, so outlines morph instead of jumping.
//

import SwiftUI

// MARK: - Figure model

/// A shape drawn in model space (y down). Only proportions matter; it is fitted into the view.
struct ShapeFigure {
    struct Label: Identifiable {
        var id: String { symbol }
        var symbol: String
        var anchor: CGPoint
        /// Direction to push the label away from the anchor, in screen orientation.
        var dir: CGVector
        var distance: CGFloat = 16
    }

    /// Right-angle marker at `vertex` between the directions to `a` and `b`.
    struct Corner {
        var vertex: CGPoint
        var a: CGPoint
        var b: CGPoint
    }

    var contours: [[CGPoint]]
    var guides: [[CGPoint]] = []
    var labels: [Label] = []
    var corners: [Corner] = []
    /// Fixed model frame (so a sector or polygon doesn't resize as it changes); nil fits the outline.
    var frame: CGRect?
    /// False when the inputs can't make this shape: a stand-in is drawn, dimmed.
    var valid = true
}

enum ShapeFigures {
    typealias Label = ShapeFigure.Label
    typealias Corner = ShapeFigure.Corner

    /// `v(symbol)` returns the entered value when it's a positive number (any consistent unit).
    static func figure(_ kind: ShapeKind, measure: CircleMeasure, _ v: (String) -> Double?) -> ShapeFigure {
        switch kind {
        case .square:
            let p = rect(1, 1)
            return ShapeFigure(contours: [p],
                               labels: [edgeLabel("a", p[2], p[3], p), edgeLabel("a ", p[3], p[0], p)],
                               corners: [Corner(vertex: p[3], a: p[0], b: p[2])])

        case .rectangle:
            let ratio = clamp(ratio(v("b"), v("a"), fallback: 0.7), 0.3, 2.2)
            let p = rect(1, ratio)
            return ShapeFigure(contours: [p],
                               labels: [edgeLabel("a", p[2], p[3], p), edgeLabel("b", p[1], p[2], p)],
                               corners: [Corner(vertex: p[3], a: p[0], b: p[2])])

        case .triangle:
            let h = clamp(ratio(v("h"), v("b"), fallback: 0.66), 0.25, 1.4)
            let apex = CGPoint(x: 0.36, y: 0)
            let p = [CGPoint(x: 0, y: h), CGPoint(x: 1, y: h), apex]
            let foot = CGPoint(x: apex.x, y: h)
            return ShapeFigure(contours: [p], guides: [[apex, foot]],
                               labels: [edgeLabel("b", p[0], p[1], p),
                                        Label(symbol: "h", anchor: mid(apex, foot), dir: CGVector(dx: 1, dy: 0), distance: 18)],
                               corners: [Corner(vertex: foot, a: apex, b: p[1])])

        case .triangleSides:
            var a = v("a") ?? 0, b = v("b") ?? 0, c = v("c") ?? 0
            let valid = ShapeKind.heron(a, b, c) != nil
            if !valid { (a, b, c) = (4, 3.4, 5) }
            // Base c along the bottom; apex where sides b (left) and a (right) meet.
            let x = (c * c + b * b - a * a) / (2 * c)
            var y = (max(0, b * b - x * x)).squareRoot() / c
            y = max(y, 0.22)
            let p = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: x / c, y: -y)]
            return ShapeFigure(contours: [p],
                               labels: [edgeLabel("c", p[0], p[1], p), edgeLabel("b", p[0], p[2], p), edgeLabel("a", p[1], p[2], p)],
                               valid: valid)

        case .rightTriangle:
            let h = clamp(ratio(v("a"), v("b"), fallback: 0.75), 0.3, 2.2)
            let p = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: h), CGPoint(x: 1, y: h)]
            return ShapeFigure(contours: [p],
                               labels: [edgeLabel("a", p[0], p[1], p), edgeLabel("b", p[1], p[2], p), edgeLabel("c", p[2], p[0], p)],
                               corners: [Corner(vertex: p[1], a: p[0], b: p[2])])

        case .circle:
            let circle = arc(center: .zero, r: 1, from: 0, to: 360, count: 72)
            let guide = measure == .radius ? [CGPoint.zero, CGPoint(x: 1, y: 0)] : [CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0)]
            let sym = measure == .radius ? "r" : "d"
            return ShapeFigure(contours: [circle], guides: [guide],
                               labels: [Label(symbol: sym, anchor: mid(guide[0], guide[1]), dir: CGVector(dx: 0, dy: -1), distance: 14)],
                               frame: CGRect(x: -1, y: -1, width: 2, height: 2))

        case .semicircle:
            // Arc over the top (y up is negative), closed along the diameter.
            let p = arc(center: .zero, r: 1, from: 180, to: 360, count: 49)
            let tip = CGPoint(x: cos(-.pi / 3.4), y: sin(-.pi / 3.4))
            let guide = measure == .radius ? [CGPoint.zero, tip] : [CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0)]
            let label = measure == .radius
                ? Label(symbol: "r", anchor: mid(.zero, tip), dir: CGVector(dx: -0.8, dy: -0.6), distance: 16)
                : Label(symbol: "d", anchor: .zero, dir: CGVector(dx: 0, dy: 1), distance: 16)
            return ShapeFigure(contours: [p], guides: [guide], labels: [label])

        case .sector:
            let theta = clamp(v("θ") ?? 60, 4, 359.5)
            let start = -90 - theta / 2, end = -90 + theta / 2
            let arcPts = arc(center: .zero, r: 1, from: start, to: end, count: 61)
            let p = [CGPoint.zero] + arcPts
            let angleArc = arc(center: .zero, r: 0.24, from: start, to: end, count: 25)
            let edge = arcPts[0]
            let bis = -90.0 * .pi / 180
            return ShapeFigure(contours: [p], guides: [angleArc],
                               labels: [Label(symbol: "r", anchor: mid(.zero, edge), dir: normal(.zero, edge, away: arcPts[30]), distance: 15),
                                        Label(symbol: "θ", anchor: CGPoint(x: cos(bis) * 0.24, y: sin(bis) * 0.24),
                                              dir: CGVector(dx: 0, dy: -1), distance: theta > 300 ? 34 : 18)],
                               frame: CGRect(x: -1, y: -1, width: 2, height: 2))

        case .ring:
            let inner = clamp(ratio(v("r"), v("R"), fallback: 0.5), 0.15, 0.86)
            let valid = (v("r") ?? 0) < (v("R") ?? 0) || v("r") == nil || v("R") == nil
            let outerPts = arc(center: .zero, r: 1, from: 0, to: 360, count: 72)
            let innerPts = arc(center: .zero, r: inner, from: 0, to: 360, count: 72)
            let oa = -35.0 * .pi / 180, ia = 145.0 * .pi / 180
            let o = CGPoint(x: cos(oa), y: sin(oa)), i = CGPoint(x: cos(ia) * inner, y: sin(ia) * inner)
            return ShapeFigure(contours: [outerPts, innerPts], guides: [[.zero, o], [.zero, i]],
                               labels: [Label(symbol: "R", anchor: CGPoint(x: o.x * 0.72, y: o.y * 0.72), dir: CGVector(dx: -0.57, dy: -0.82), distance: 14),
                                        Label(symbol: "r", anchor: mid(.zero, i), dir: CGVector(dx: -0.57, dy: -0.82), distance: 14)],
                               frame: CGRect(x: -1, y: -1, width: 2, height: 2), valid: valid)

        case .ellipse:
            let ry = clamp(ratio(v("b"), v("a"), fallback: 0.66), 0.28, 1.6)
            let p = (0..<72).map { k -> CGPoint in
                let t = Double(k) / 72 * 2 * .pi
                return CGPoint(x: cos(t), y: sin(t) * ry)
            }
            let top = CGPoint(x: 0, y: -ry)
            return ShapeFigure(contours: [p], guides: [[.zero, CGPoint(x: 1, y: 0)], [.zero, top]],
                               labels: [Label(symbol: "a", anchor: CGPoint(x: 0.5, y: 0), dir: CGVector(dx: 0, dy: 1), distance: 13),
                                        Label(symbol: "b", anchor: mid(.zero, top), dir: CGVector(dx: -1, dy: 0), distance: 16)],
                               corners: [Corner(vertex: .zero, a: CGPoint(x: 1, y: 0), b: top)])

        case .trapezoid:
            let a = v("a") ?? 6, b = v("b") ?? 4
            let longer = max(a, b)
            let bt = clamp(b / a, 0.15, 2.2)
            let h = clamp((v("h") ?? 3) / a, 0.2, max(1, bt))
            var left = (1 - bt) / 2
            if let c = v("c"), let d = v("d"), let hv = v("h"), c >= hv, d >= hv,
               ShapeKind.trapezoidFits(a: a, b: b, h: hv, c: c, d: d) {
                let pc = (c * c - hv * hv).squareRoot(), pd = (d * d - hv * hv).squareRoot()
                // Legs leaning in from both ends (the usual case), else the same way.
                left = abs(pc + pd - abs(a - b)) <= 0.01 * longer
                    ? (a >= b ? pc / a : -pc / a)
                    : (pc > pd ? pc / a : -pc / a)
            }
            let p = [CGPoint(x: 0, y: h), CGPoint(x: 1, y: h), CGPoint(x: left + bt, y: 0), CGPoint(x: left, y: 0)]
            let gx = (max(0, left) + min(1, left + bt)) / 2
            let top = CGPoint(x: gx, y: 0), foot = CGPoint(x: gx, y: h)
            return ShapeFigure(contours: [p], guides: [[top, foot]],
                               labels: [edgeLabel("a", p[0], p[1], p), edgeLabel("b", p[2], p[3], p),
                                        edgeLabel("c", p[3], p[0], p), edgeLabel("d", p[1], p[2], p),
                                        Label(symbol: "h", anchor: mid(top, foot), dir: CGVector(dx: 1, dy: 0), distance: 16)],
                               corners: [Corner(vertex: foot, a: top, b: p[1])])

        case .parallelogram:
            let base = v("b") ?? 5
            let side = v("s") ?? 3, hv = v("h") ?? 2.5
            let valid = hv <= side || v("h") == nil || v("s") == nil
            let h = clamp(hv / base, 0.2, 1.0)
            let slant = valid ? (max(0, side * side - hv * hv)).squareRoot() / hv : 0.5
            let o = clamp(h * slant, 0, 1.1)
            let p = [CGPoint(x: 0, y: h), CGPoint(x: 1, y: h), CGPoint(x: 1 + o, y: 0), CGPoint(x: o, y: 0)]
            let foot = CGPoint(x: o, y: h)
            return ShapeFigure(contours: [p], guides: [[p[3], foot]],
                               labels: [edgeLabel("b", p[0], p[1], p), edgeLabel("s", p[1], p[2], p),
                                        Label(symbol: "h", anchor: mid(p[3], foot), dir: CGVector(dx: o < 0.25 ? 1 : -1, dy: 0), distance: 16)],
                               corners: [Corner(vertex: foot, a: p[3], b: p[1])], valid: valid)

        case .rhombus:
            let r = clamp(ratio(v("d₂"), v("d₁"), fallback: 0.66), 0.3, 2.2)
            let p = [CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -r), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: r)]
            return ShapeFigure(contours: [p], guides: [[p[0], p[2]], [p[1], p[3]]],
                               labels: [Label(symbol: "d₁", anchor: CGPoint(x: -0.5, y: 0), dir: CGVector(dx: 0, dy: 1), distance: 13),
                                        Label(symbol: "d₂", anchor: CGPoint(x: 0, y: -r / 2), dir: CGVector(dx: 1, dy: 0), distance: 18)],
                               corners: [Corner(vertex: .zero, a: p[2], b: p[1])])

        case .regularPolygon:
            let n = Int(clamp((v("n") ?? 6).rounded(), 3, 48))
            let step = 360.0 / Double(n)
            var p = (0..<n).map { k -> CGPoint in
                let t = (90 + step / 2 + Double(k) * step) * .pi / 180
                return CGPoint(x: cos(t), y: sin(t))
            }
            // Pad to a fixed count so changing n morphs (new corners grow out of the last one).
            while p.count < 48 { p.append(p[n - 1]) }
            let apothem = CGPoint(x: 0, y: cos(.pi / Double(n)))
            return ShapeFigure(contours: [p], guides: [[.zero, apothem]],
                               labels: [edgeLabel("s", p[0], p[n - 1], Array(p.prefix(n))),
                                        Label(symbol: "n", anchor: .zero, dir: CGVector(dx: 0, dy: -1), distance: 14)],
                               frame: CGRect(x: -1, y: -1, width: 2, height: 2))
        }
    }

    // MARK: Helpers

    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }

    static func ratio(_ num: Double?, _ den: Double?, fallback: Double) -> Double {
        guard let num, let den, den > 0 else { return fallback }
        return num / den
    }

    static func rect(_ w: Double, _ h: Double) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: w, y: h), CGPoint(x: 0, y: h)]
    }

    static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    static func arc(center: CGPoint, r: Double, from: Double, to: Double, count: Int) -> [CGPoint] {
        let span: Double = to - from
        // A full turn doesn't repeat its first point; a partial arc includes both ends.
        let steps: Double = Double(span >= 360 ? count : count - 1)
        return (0..<count).map { (k: Int) -> CGPoint in
            let deg: Double = from + span * Double(k) / steps
            let t: Double = deg * Double.pi / 180
            return CGPoint(x: Double(center.x) + cos(t) * r, y: Double(center.y) + sin(t) * r)
        }
    }

    /// Unit normal of edge a-b pointing away from `away`.
    static func normal(_ a: CGPoint, _ b: CGPoint, away: CGPoint) -> CGVector {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1e-9, (dx * dx + dy * dy).squareRoot())
        var n = CGVector(dx: -dy / len, dy: dx / len)
        let m = mid(a, b)
        if (m.x - away.x) * n.dx + (m.y - away.y) * n.dy < 0 { n = CGVector(dx: -n.dx, dy: -n.dy) }
        return n
    }

    /// Label at the middle of an edge, pushed outward from the polygon's centroid.
    static func edgeLabel(_ symbol: String, _ a: CGPoint, _ b: CGPoint, _ poly: [CGPoint]) -> ShapeFigure.Label {
        let c = CGPoint(x: poly.map(\.x).reduce(0, +) / CGFloat(poly.count), y: poly.map(\.y).reduce(0, +) / CGFloat(poly.count))
        return ShapeFigure.Label(symbol: symbol, anchor: mid(a, b), dir: normal(a, b, away: c))
    }
}

// MARK: - Animatable point list

/// Flat list of coordinates that SwiftUI can interpolate. Lists of different lengths pad with zeros,
/// which never happens in practice because each shape keeps a fixed point count.
struct PointList: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double] = []) { self.values = values }
    init(points: [[CGPoint]]) { values = points.flatMap { $0.flatMap { [Double($0.x), Double($0.y)] } } }

    static var zero: PointList { PointList() }

    private static func combine(_ l: PointList, _ r: PointList, _ op: (Double, Double) -> Double) -> PointList {
        let n = max(l.values.count, r.values.count)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = op(i < l.values.count ? l.values[i] : 0, i < r.values.count ? r.values[i] : 0)
        }
        return PointList(out)
    }

    static func + (l: PointList, r: PointList) -> PointList { combine(l, r, +) }
    static func - (l: PointList, r: PointList) -> PointList { combine(l, r, -) }
    static func += (l: inout PointList, r: PointList) { l = l + r }
    static func -= (l: inout PointList, r: PointList) { l = l - r }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

/// Polylines from a flat point list. `counts` splits it into separate subpaths.
struct AnimatedPolylines: Shape {
    var data: PointList
    var counts: [Int]
    var closed: Bool

    var animatableData: PointList {
        get { data }
        set { data = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var i = 0
        let v = data.values
        for count in counts {
            guard count > 0, (i + count) * 2 <= v.count else { break }
            p.move(to: CGPoint(x: v[i * 2], y: v[i * 2 + 1]))
            for k in 1..<max(1, count) where count > 1 {
                p.addLine(to: CGPoint(x: v[(i + k) * 2], y: v[(i + k) * 2 + 1]))
            }
            if closed { p.closeSubpath() }
            i += count
        }
        return p
    }
}

// MARK: - View

/// Draws a shape fitted into its frame. With `labelText` it adds dimension labels; without, it's a plain icon.
struct ShapeDiagramView: View {
    var kind: ShapeKind
    var measure: CircleMeasure = .radius
    /// Entered values by symbol (positive numbers only; any consistent unit).
    var values: [String: Double] = [:]
    /// Label text per symbol ("a = 4.2 m"). Nil draws no labels.
    var labelText: ((String) -> String)?
    var lineWidth: CGFloat = 2
    var inset: CGFloat = 40
    var showGuides = true

    var body: some View {
        GeometryReader { g in
            let fig = ShapeFigures.figure(kind, measure: measure) { s in
                values[s].flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
            }
            let map = Self.mapper(fig, size: g.size, inset: inset)
            let contours = fig.contours.map { $0.map(map) }
            let guides = fig.guides.map { $0.map(map) }
            let corners = fig.corners.map { Self.cornerPath(map($0.vertex), map($0.a), map($0.b)) }
            let tint = fig.valid ? PM.Colors.accent : PM.Colors.warning

            ZStack(alignment: .topLeading) {
                AnimatedPolylines(data: PointList(points: contours), counts: contours.map(\.count), closed: true)
                    .fill(tint.opacity(fig.valid ? 0.14 : 0.08), style: FillStyle(eoFill: true))
                AnimatedPolylines(data: PointList(points: contours), counts: contours.map(\.count), closed: true)
                    .stroke(tint.opacity(fig.valid ? 1 : 0.7),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round,
                                               dash: fig.valid ? [] : [6, 4]))
                if showGuides {
                    AnimatedPolylines(data: PointList(points: guides), counts: guides.map(\.count), closed: false)
                        .stroke(PM.Colors.textSecondary.opacity(0.8),
                                style: StrokeStyle(lineWidth: max(1, lineWidth * 0.6), lineCap: .round, dash: [4, 4]))
                    AnimatedPolylines(data: PointList(points: corners), counts: corners.map(\.count), closed: false)
                        .stroke(PM.Colors.textSecondary.opacity(0.8), lineWidth: 1)
                }
                if let labelText {
                    ForEach(fig.labels) { l in
                        let a = map(l.anchor)
                        let text = labelText(l.symbol.trimmingCharacters(in: .whitespaces))
                        let w = CGFloat(text.count) * 7.4 + 18
                        let x = min(max(a.x + l.dir.dx * (l.distance + abs(l.dir.dx) * w * 0.38), w / 2 + 4), g.size.width - w / 2 - 4)
                        let y = min(max(a.y + l.dir.dy * l.distance, 14), g.size.height - 14)
                        DimensionChip(symbol: l.symbol.trimmingCharacters(in: .whitespaces), text: text)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }

    /// Fits the figure's frame into `size` minus `inset`, keeping proportions, centred.
    private static func mapper(_ fig: ShapeFigure, size: CGSize, inset: CGFloat) -> (CGPoint) -> CGPoint {
        let pts = fig.contours.flatMap { $0 }
        let box: CGRect = fig.frame ?? {
            let xs = pts.map(\.x), ys = pts.map(\.y)
            let minX = xs.min() ?? 0, minY = ys.min() ?? 0
            return CGRect(x: minX, y: minY, width: max(1e-6, (xs.max() ?? 1) - minX), height: max(1e-6, (ys.max() ?? 1) - minY))
        }()
        let availW = max(10, size.width - inset * 2), availH = max(10, size.height - inset * 2)
        let s = min(availW / box.width, availH / box.height)
        let ox = (size.width - box.width * s) / 2 - box.minX * s
        let oy = (size.height - box.height * s) / 2 - box.minY * s
        return { p in CGPoint(x: p.x * s + ox, y: p.y * s + oy) }
    }

    /// Small right-angle square at `v`, 9 pt along each edge.
    private static func cornerPath(_ v: CGPoint, _ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
        func unit(_ p: CGPoint) -> CGVector {
            let dx = p.x - v.x, dy = p.y - v.y
            let l = max(1e-6, (dx * dx + dy * dy).squareRoot())
            return CGVector(dx: dx / l * 9, dy: dy / l * 9)
        }
        let ua = unit(a), ub = unit(b)
        return [CGPoint(x: v.x + ua.dx, y: v.y + ua.dy),
                CGPoint(x: v.x + ua.dx + ub.dx, y: v.y + ua.dy + ub.dy),
                CGPoint(x: v.x + ub.dx, y: v.y + ub.dy)]
    }
}

/// "a = 4.2 m" pill on the diagram.
private struct DimensionChip: View {
    var symbol: String
    var text: String

    var body: some View {
        Text(text)
            .font(.pm(12, .semibold))
            .monospacedDigit()
            .foregroundStyle(PM.Colors.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(PM.Colors.surfaceRaised))
            .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
            .contentTransition(.numericText())
    }
}
