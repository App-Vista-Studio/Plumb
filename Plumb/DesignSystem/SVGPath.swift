//
//  SVGPath.swift
//  Plumb
//
//  Parses SVG path data (the `d` attribute) into a SwiftUI Path so icons and
//  diagram strokes can be copied straight from the design boards.
//  Supports M L H V C S Q T A Z in absolute and relative forms.
//

import SwiftUI

nonisolated enum SVG {

    // MARK: Element helpers (convert <circle>, <rect>, <line> into path data)

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> String {
        "M\(cx - r) \(cy)a\(r) \(r) 0 1 0 \(2 * r) 0a\(r) \(r) 0 1 0 \(-2 * r) 0z"
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, rx: CGFloat = 0) -> String {
        let r = min(rx, w / 2, h / 2)
        if r <= 0 { return "M\(x) \(y)h\(w)v\(h)h\(-w)z" }
        return "M\(x + r) \(y)h\(w - 2 * r)a\(r) \(r) 0 0 1 \(r) \(r)v\(h - 2 * r)a\(r) \(r) 0 0 1 \(-r) \(r)h\(-(w - 2 * r))a\(r) \(r) 0 0 1 \(-r) \(-r)v\(-(h - 2 * r))a\(r) \(r) 0 0 1 \(r) \(-r)z"
    }

    static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> String {
        "M\(x1) \(y1)L\(x2) \(y2)"
    }

    // MARK: Parsing

    nonisolated(unsafe) private static var cache: [String: Path] = [:]
    private static let lock = NSLock()

    /// Parsed path in the SVG's own coordinate space. Results are cached.
    static func path(_ d: String) -> Path {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[d] { return hit }
        var parser = Parser(d)
        let p = parser.parse()
        cache[d] = p
        return p
    }

    private struct Parser {
        private let chars: [Character]
        private var i = 0

        init(_ d: String) { chars = Array(d) }

        mutating func parse() -> Path {
            var path = Path()
            var cmd: Character = " "
            var current = CGPoint.zero
            var start = CGPoint.zero
            var lastControl: CGPoint?
            var lastCmd: Character = " "

            while true {
                skipSeparators()
                guard i < chars.count else { break }
                let c = chars[i]
                if c.isLetter {
                    cmd = c
                    i += 1
                } else if cmd == " " {
                    i += 1
                    continue
                }
                let rel = cmd.isLowercase
                let base = rel ? current : .zero

                switch cmd.uppercased().first! {
                case "M":
                    guard let x = number(), let y = number() else { i += 1; continue }
                    current = CGPoint(x: base.x + x, y: base.y + y)
                    start = current
                    path.move(to: current)
                    cmd = rel ? "l" : "L" // implicit lineto after the first pair
                    lastControl = nil
                case "L":
                    guard let x = number(), let y = number() else { i += 1; continue }
                    current = CGPoint(x: base.x + x, y: base.y + y)
                    path.addLine(to: current)
                    lastControl = nil
                case "H":
                    guard let x = number() else { i += 1; continue }
                    current = CGPoint(x: (rel ? current.x : 0) + x, y: current.y)
                    path.addLine(to: current)
                    lastControl = nil
                case "V":
                    guard let y = number() else { i += 1; continue }
                    current = CGPoint(x: current.x, y: (rel ? current.y : 0) + y)
                    path.addLine(to: current)
                    lastControl = nil
                case "C":
                    guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(),
                          let x = number(), let y = number() else { i += 1; continue }
                    let c1 = CGPoint(x: base.x + x1, y: base.y + y1)
                    let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                    current = CGPoint(x: base.x + x, y: base.y + y)
                    path.addCurve(to: current, control1: c1, control2: c2)
                    lastControl = c2
                case "S":
                    guard let x2 = number(), let y2 = number(), let x = number(), let y = number() else { i += 1; continue }
                    let c1: CGPoint
                    if let lc = lastControl, "CcSs".contains(lastCmd) {
                        c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                    } else { c1 = current }
                    let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                    current = CGPoint(x: base.x + x, y: base.y + y)
                    path.addCurve(to: current, control1: c1, control2: c2)
                    lastControl = c2
                case "Q":
                    guard let x1 = number(), let y1 = number(), let x = number(), let y = number() else { i += 1; continue }
                    let c = CGPoint(x: base.x + x1, y: base.y + y1)
                    current = CGPoint(x: base.x + x, y: base.y + y)
                    path.addQuadCurve(to: current, control: c)
                    lastControl = c
                case "T":
                    guard let x = number(), let y = number() else { i += 1; continue }
                    let c: CGPoint
                    if let lc = lastControl, "QqTt".contains(lastCmd) {
                        c = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                    } else { c = current }
                    current = CGPoint(x: base.x + x, y: base.y + y)
                    path.addQuadCurve(to: current, control: c)
                    lastControl = c
                case "A":
                    guard let rx = number(), let ry = number(), let rot = number(),
                          let large = flag(), let sweep = flag(),
                          let x = number(), let y = number() else { i += 1; continue }
                    let end = CGPoint(x: base.x + x, y: base.y + y)
                    SVG.addArc(to: &path, from: current, to: end, rx: rx, ry: ry,
                               rotation: rot, largeArc: large, sweep: sweep)
                    current = end
                    lastControl = nil
                case "Z":
                    path.closeSubpath()
                    current = start
                    lastControl = nil
                default:
                    i += 1
                }
                lastCmd = cmd
            }
            return path
        }

        private mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }

        /// Arc flags may be written without separators ("a4 4 0 0110 8").
        private mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count else { return nil }
            if chars[i] == "0" { i += 1; return false }
            if chars[i] == "1" { i += 1; return true }
            return nil
        }

        private mutating func number() -> CGFloat? {
            skipSeparators()
            guard i < chars.count else { return nil }
            var s = ""
            if chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            var seenDot = false, seenExp = false
            while i < chars.count {
                let ch = chars[i]
                if ch.isNumber { s.append(ch); i += 1 }
                else if ch == "." && !seenDot && !seenExp { seenDot = true; s.append(ch); i += 1 }
                else if (ch == "e" || ch == "E") && !seenExp && !s.isEmpty {
                    seenExp = true; s.append(ch); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
                } else { break }
            }
            guard let v = Double(s) else { return nil }
            return CGFloat(v)
        }
    }

    /// Endpoint-parameterised elliptical arc to cubic Béziers (SVG spec F.6).
    fileprivate static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint,
                                   rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat,
                                   largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || p0 == p1 { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = sqrt(max(0, num / den))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / CGFloat(segments)
        let t = 4 / 3 * tan(delta / 4)
        var th = theta1
        for _ in 0..<segments {
            let cos1 = cos(th), sin1 = sin(th)
            let cos2 = cos(th + delta), sin2 = sin(th + delta)
            func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cx + rx * x * cosPhi - ry * y * sinPhi,
                        y: cy + rx * x * sinPhi + ry * y * cosPhi)
            }
            let c1 = map(cos1 - t * sin1, sin1 + t * cos1)
            let c2 = map(cos2 + t * sin2, sin2 - t * cos2)
            let e = map(cos2, sin2)
            path.addCurve(to: e, control1: c1, control2: c2)
            th += delta
        }
    }
}

// MARK: - Shapes

/// SVG path data drawn in a `viewBox` and scaled to fit the proposed frame.
nonisolated struct SVGShape: Shape {
    var d: String
    var viewBox: CGRect = CGRect(x: 0, y: 0, width: 24, height: 24)

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / viewBox.width
        let sy = rect.height / viewBox.height
        let t = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: sx, y: sy)
            .translatedBy(x: -viewBox.minX, y: -viewBox.minY)
        return SVG.path(d).applying(t)
    }
}

/// A stroked SVG glyph, matching `<svg fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">`.
/// `lineWidth` is in viewBox units, like the SVG `stroke-width`.
struct SVGStroke: View {
    var d: String
    var size: CGFloat = 24
    var lineWidth: CGFloat = 1.7
    var viewBox: CGFloat = 24

    var body: some View {
        SVGShape(d: d, viewBox: CGRect(x: 0, y: 0, width: viewBox, height: viewBox))
            .stroke(style: StrokeStyle(lineWidth: lineWidth * size / viewBox, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
