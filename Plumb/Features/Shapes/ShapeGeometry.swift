//
//  ShapeGeometry.swift
//  Plumb
//
//  Pure geometry for the Shape Area calculators: shapes, their inputs, area, perimeter and formulas,
//  plus exact length and area unit factors and the number formatting used to show results.
//
//  Foundation only, so it compiles standalone with `swiftc` for the numeric checks.
//  Every length is in metres (SI) internally; angles are in degrees; counts are plain numbers.
//

import Foundation

// MARK: - Units

/// Input length units. Factors are the exact international definitions (metres per unit).
enum ShapeLengthUnit: String, CaseIterable, Identifiable, Hashable, Codable {
    case mm, cm, m, km, `in`, ft, yd, mi

    var id: String { rawValue }
    var symbol: String { rawValue }

    /// Metres per unit, exact by definition (1 in = 0.0254 m, 1 ft = 0.3048 m, 1 yd = 0.9144 m, 1 mi = 1609.344 m).
    var metres: Double {
        switch self {
        case .mm: 0.001
        case .cm: 0.01
        case .m: 1
        case .km: 1000
        case .in: 0.0254
        case .ft: 0.3048
        case .yd: 0.9144
        case .mi: 1609.344
        }
    }

    var spoken: String {
        switch self {
        case .mm: "millimetres"
        case .cm: "centimetres"
        case .m: "metres"
        case .km: "kilometres"
        case .in: "inches"
        case .ft: "feet"
        case .yd: "yards"
        case .mi: "miles"
        }
    }
}

/// Output area units. Each square factor is derived by squaring the exact length factor.
enum ShapeAreaUnit: String, CaseIterable, Identifiable, Hashable, Codable {
    case mm2, cm2, m2, ha, km2, in2, ft2, yd2, acre, mi2

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .mm2: "mm²"
        case .cm2: "cm²"
        case .m2: "m²"
        case .ha: "ha"
        case .km2: "km²"
        case .in2: "in²"
        case .ft2: "ft²"
        case .yd2: "yd²"
        case .acre: "acre"
        case .mi2: "mi²"
        }
    }

    var spoken: String {
        switch self {
        case .mm2: "square millimetres"
        case .cm2: "square centimetres"
        case .m2: "square metres"
        case .ha: "hectares"
        case .km2: "square kilometres"
        case .in2: "square inches"
        case .ft2: "square feet"
        case .yd2: "square yards"
        case .acre: "acres"
        case .mi2: "square miles"
        }
    }

    /// The length unit perimeters are shown in alongside this area unit.
    var perimeterUnit: ShapeLengthUnit {
        switch self {
        case .mm2: .mm
        case .cm2: .cm
        case .m2, .ha: .m
        case .km2: .km
        case .in2: .in
        case .ft2, .acre: .ft
        case .yd2: .yd
        case .mi2: .mi
        }
    }

    /// Square metres per unit. 1 ha = 10 000 m²; 1 international acre = 43 560 ft² = 4046.8564224 m².
    var squareMetres: Double {
        switch self {
        case .ha: 10_000
        case .acre: 4046.856_422_4
        default: perimeterUnit.metres * perimeterUnit.metres
        }
    }

    /// The natural output for an input unit (m -> m², ft -> ft²).
    static func matching(_ unit: ShapeLengthUnit) -> ShapeAreaUnit {
        switch unit {
        case .mm: .mm2
        case .cm: .cm2
        case .m: .m2
        case .km: .km2
        case .in: .in2
        case .ft: .ft2
        case .yd: .yd2
        case .mi: .mi2
        }
    }
}

// MARK: - Inputs

struct ShapeInput: Identifiable, Hashable {
    enum Kind: Hashable { case length, angle, count }

    /// Stable key, also the symbol used in formulas.
    var id: String { symbol }
    var name: String
    var symbol: String
    var kind: Kind = .length
    var optional = false
    /// Starting value (in the input unit for lengths).
    var defaultValue: String
}

/// Circle and semicircle can be entered by radius or diameter.
enum CircleMeasure: String, CaseIterable, Hashable, Codable {
    case radius, diameter
}

// MARK: - Results

struct ShapeExtra: Hashable {
    enum Kind: Hashable { case length, angle }
    var name: String
    var symbol: String
    /// Metres for lengths, degrees for angles.
    var value: Double
    var kind: Kind = .length
}

struct ShapeResult: Hashable {
    /// Square metres.
    var area: Double
    /// Metres, nil when the inputs can't determine it.
    var perimeter: Double?
    /// True when the perimeter is an approximation (ellipse).
    var perimeterIsApproximate = false
    /// Why the perimeter is missing, or how to read it.
    var perimeterNote: String?
    /// Derived lengths and angles worth showing (hypotenuse, side, arc length...).
    var extras: [ShapeExtra] = []
    /// Non-blocking warnings (measurements that don't quite agree).
    var notes: [String] = []
}

enum ShapeError: Error, Hashable {
    case missing(String)
    case notANumber(String)
    case notPositive(String)
    case notWhole(String)
    case outOfRange(String)
    case impossible(String)

    var message: String {
        switch self {
        case .missing(let name): "Enter \(name) to see the result."
        case .notANumber(let name): "\(name) isn't a number."
        case .notPositive(let name): "\(name) must be more than 0."
        case .notWhole(let name): "\(name) must be a whole number."
        case .outOfRange(let s), .impossible(let s): s
        }
    }
}

// MARK: - Shapes

enum ShapeKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case square, rectangle, triangle, triangleSides, rightTriangle, circle, semicircle, sector,
         ring, ellipse, trapezoid, parallelogram, rhombus, regularPolygon

    var id: String { rawValue }

    var name: String {
        switch self {
        case .square: "Square"
        case .rectangle: "Rectangle"
        case .triangle: "Triangle"
        case .triangleSides: "Triangle (3 sides)"
        case .rightTriangle: "Right Triangle"
        case .circle: "Circle"
        case .semicircle: "Semicircle"
        case .sector: "Sector"
        case .ring: "Ring"
        case .ellipse: "Ellipse"
        case .trapezoid: "Trapezoid"
        case .parallelogram: "Parallelogram"
        case .rhombus: "Rhombus"
        case .regularPolygon: "Regular Polygon"
        }
    }

    /// One-line hint for tiles.
    var hint: String {
        switch self {
        case .square: "A = a²"
        case .rectangle: "A = a × b"
        case .triangle: "A = ½ b × h"
        case .triangleSides: "Heron's formula"
        case .rightTriangle: "A = ½ a × b"
        case .circle: "A = π r²"
        case .semicircle: "A = ½ π r²"
        case .sector: "A = θ⁄360 × π r²"
        case .ring: "A = π (R² − r²)"
        case .ellipse: "A = π a b"
        case .trapezoid: "A = ½ (a + b) h"
        case .parallelogram: "A = b × h"
        case .rhombus: "A = ½ d₁ × d₂"
        case .regularPolygon: "A = n s² ⁄ 4 tan(π⁄n)"
        }
    }

    var usesCircleMeasure: Bool { self == .circle || self == .semicircle }

    func inputs(_ measure: CircleMeasure = .radius) -> [ShapeInput] {
        switch self {
        case .square:
            [ShapeInput(name: "Side", symbol: "a", defaultValue: "10")]
        case .rectangle:
            [ShapeInput(name: "Length", symbol: "a", defaultValue: "4.2"),
             ShapeInput(name: "Width", symbol: "b", defaultValue: "3.8")]
        case .triangle:
            [ShapeInput(name: "Base", symbol: "b", defaultValue: "6"),
             ShapeInput(name: "Height", symbol: "h", defaultValue: "4")]
        case .triangleSides:
            [ShapeInput(name: "Side", symbol: "a", defaultValue: "3"),
             ShapeInput(name: "Side", symbol: "b", defaultValue: "4"),
             ShapeInput(name: "Side", symbol: "c", defaultValue: "5")]
        case .rightTriangle:
            [ShapeInput(name: "Leg", symbol: "a", defaultValue: "3"),
             ShapeInput(name: "Leg", symbol: "b", defaultValue: "4")]
        case .circle, .semicircle:
            measure == .radius
                ? [ShapeInput(name: "Radius", symbol: "r", defaultValue: "1.5")]
                : [ShapeInput(name: "Diameter", symbol: "d", defaultValue: "3")]
        case .sector:
            [ShapeInput(name: "Radius", symbol: "r", defaultValue: "2"),
             ShapeInput(name: "Angle", symbol: "θ", kind: .angle, defaultValue: "60")]
        case .ring:
            [ShapeInput(name: "Outer radius", symbol: "R", defaultValue: "2"),
             ShapeInput(name: "Inner radius", symbol: "r", defaultValue: "1")]
        case .ellipse:
            [ShapeInput(name: "Semi-axis", symbol: "a", defaultValue: "3"),
             ShapeInput(name: "Semi-axis", symbol: "b", defaultValue: "2")]
        case .trapezoid:
            [ShapeInput(name: "Base", symbol: "a", defaultValue: "6"),
             ShapeInput(name: "Top", symbol: "b", defaultValue: "4"),
             ShapeInput(name: "Height", symbol: "h", defaultValue: "3"),
             ShapeInput(name: "Leg", symbol: "c", optional: true, defaultValue: ""),
             ShapeInput(name: "Leg", symbol: "d", optional: true, defaultValue: "")]
        case .parallelogram:
            [ShapeInput(name: "Base", symbol: "b", defaultValue: "5"),
             ShapeInput(name: "Side", symbol: "s", defaultValue: "3"),
             ShapeInput(name: "Height", symbol: "h", defaultValue: "2.5")]
        case .rhombus:
            [ShapeInput(name: "Diagonal", symbol: "d₁", defaultValue: "6"),
             ShapeInput(name: "Diagonal", symbol: "d₂", defaultValue: "4")]
        case .regularPolygon:
            [ShapeInput(name: "Sides", symbol: "n", kind: .count, defaultValue: "6"),
             ShapeInput(name: "Side length", symbol: "s", defaultValue: "2")]
        }
    }

    // MARK: Formulas

    /// Symbolic area formula.
    func areaFormula(_ measure: CircleMeasure = .radius) -> String {
        switch self {
        case .circle: measure == .radius ? "A = π r²" : "A = π d² ⁄ 4"
        case .semicircle: measure == .radius ? "A = π r² ⁄ 2" : "A = π d² ⁄ 8"
        case .triangleSides: "A = √(p (p − a)(p − b)(p − c)), p = (a + b + c) ⁄ 2"
        case .regularPolygon: "A = n s² ⁄ (4 tan(π ⁄ n))"
        case .sector: "A = θ ⁄ 360 × π r²"
        case .rhombus: "A = d₁ × d₂ ⁄ 2"
        case .trapezoid: "A = (a + b) ⁄ 2 × h"
        case .triangle: "A = b × h ⁄ 2"
        case .rightTriangle: "A = a × b ⁄ 2"
        default: hint
        }
    }

    /// Symbolic perimeter formula, nil when this shape's inputs never determine one.
    func perimeterFormula(_ measure: CircleMeasure = .radius) -> String? {
        switch self {
        case .square: "P = 4a"
        case .rectangle: "P = 2 (a + b)"
        case .triangle: nil
        case .triangleSides: "P = a + b + c"
        case .rightTriangle: "P = a + b + c, c = √(a² + b²)"
        case .circle: measure == .radius ? "C = 2 π r" : "C = π d"
        case .semicircle: measure == .radius ? "P = π r + 2r" : "P = π d ⁄ 2 + d"
        case .sector: "P = 2r + θ ⁄ 360 × 2 π r"
        case .ring: "P = 2 π R + 2 π r"
        case .ellipse: "P ≈ π (a + b)(1 + 3λ ⁄ (10 + √(4 − 3λ))), λ = ((a − b) ⁄ (a + b))²"
        case .trapezoid: "P = a + b + c + d"
        case .parallelogram: "P = 2 (b + s)"
        case .rhombus: "P = 4s, s = √((d₁ ⁄ 2)² + (d₂ ⁄ 2)²)"
        case .regularPolygon: "P = n × s"
        }
    }

    /// Area expression with the entered numbers substituted, e.g. "4.2 × 3.8". `v` returns a value as typed.
    func areaSubstitution(_ measure: CircleMeasure, _ v: (String) -> String) -> String {
        switch self {
        case .square: "\(v("a"))²"
        case .rectangle: "\(v("a")) × \(v("b"))"
        case .triangle: "\(v("b")) × \(v("h")) ⁄ 2"
        case .triangleSides: "√(p (p − \(v("a")))(p − \(v("b")))(p − \(v("c"))))"
        case .rightTriangle: "\(v("a")) × \(v("b")) ⁄ 2"
        case .circle: measure == .radius ? "π × \(v("r"))²" : "π × \(v("d"))² ⁄ 4"
        case .semicircle: measure == .radius ? "π × \(v("r"))² ⁄ 2" : "π × \(v("d"))² ⁄ 8"
        case .sector: "\(v("θ")) ⁄ 360 × π × \(v("r"))²"
        case .ring: "π (\(v("R"))² − \(v("r"))²)"
        case .ellipse: "π × \(v("a")) × \(v("b"))"
        case .trapezoid: "(\(v("a")) + \(v("b"))) ⁄ 2 × \(v("h"))"
        case .parallelogram: "\(v("b")) × \(v("h"))"
        case .rhombus: "\(v("d₁")) × \(v("d₂")) ⁄ 2"
        case .regularPolygon: "\(v("n")) × \(v("s"))² ⁄ (4 tan(π ⁄ \(v("n"))))"
        }
    }

    /// Perimeter expression with the entered numbers substituted, nil when there's no perimeter formula.
    func perimeterSubstitution(_ measure: CircleMeasure, _ v: (String) -> String) -> String? {
        switch self {
        case .square: "4 × \(v("a"))"
        case .rectangle: "2 × (\(v("a")) + \(v("b")))"
        case .triangle: nil
        case .triangleSides: "\(v("a")) + \(v("b")) + \(v("c"))"
        case .rightTriangle: "\(v("a")) + \(v("b")) + √(\(v("a"))² + \(v("b"))²)"
        case .circle: measure == .radius ? "2 × π × \(v("r"))" : "π × \(v("d"))"
        case .semicircle: measure == .radius ? "π × \(v("r")) + 2 × \(v("r"))" : "π × \(v("d")) ⁄ 2 + \(v("d"))"
        case .sector: "2 × \(v("r")) + \(v("θ")) ⁄ 360 × 2π × \(v("r"))"
        case .ring: "2π × \(v("R")) + 2π × \(v("r"))"
        case .ellipse: "π (\(v("a")) + \(v("b")))(1 + 3λ ⁄ (10 + √(4 − 3λ)))"
        case .trapezoid: "\(v("a")) + \(v("b")) + \(v("c")) + \(v("d"))"
        case .parallelogram: "2 × (\(v("b")) + \(v("s")))"
        case .rhombus: "4 × √((\(v("d₁")) ⁄ 2)² + (\(v("d₂")) ⁄ 2)²)"
        case .regularPolygon: "\(v("n")) × \(v("s"))"
        }
    }

    // MARK: Compute

    /// Area and perimeter from parsed inputs keyed by symbol. Lengths in metres, angles in degrees.
    /// Missing optional inputs are simply absent from `values`.
    func compute(_ values: [String: Double], measure: CircleMeasure = .radius) -> Result<ShapeResult, ShapeError> {
        let specs = inputs(measure)
        // Validate every input first so the message names the first problem in reading order.
        for spec in specs {
            guard let v = values[spec.symbol] else {
                if spec.optional { continue }
                return .failure(.missing("\(spec.name.lowercased()) \(spec.symbol)"))
            }
            guard v.isFinite else { return .failure(.notANumber("\(spec.name) \(spec.symbol)")) }
            guard v > 0 else { return .failure(.notPositive("\(spec.name) \(spec.symbol)")) }
            if spec.kind == .count, v != v.rounded() { return .failure(.notWhole("\(spec.name) \(spec.symbol)")) }
        }
        func x(_ k: String) -> Double { values[k] ?? 0 }

        var r: ShapeResult
        switch self {
        case .square:
            let a = x("a")
            r = ShapeResult(area: a * a, perimeter: 4 * a,
                            extras: [ShapeExtra(name: "Diagonal", symbol: "d", value: a * 2.0.squareRoot())])

        case .rectangle:
            let a = x("a"), b = x("b")
            r = ShapeResult(area: a * b, perimeter: 2 * (a + b),
                            extras: [ShapeExtra(name: "Diagonal", symbol: "d", value: hypot(a, b))])

        case .triangle:
            let b = x("b"), h = x("h")
            r = ShapeResult(area: b * h / 2, perimeter: nil,
                            perimeterNote: "Base and height don't fix the other two sides. Use Triangle (3 sides) for the perimeter.")

        case .triangleSides:
            let a = x("a"), b = x("b"), c = x("c")
            guard let area = Self.heron(a, b, c) else {
                return .failure(.impossible("These sides can't make a triangle: each side must be shorter than the other two added together."))
            }
            let longest = max(a, b, c)
            r = ShapeResult(area: area, perimeter: a + b + c,
                            extras: [ShapeExtra(name: "Height to longest side", symbol: "h", value: 2 * area / longest)])

        case .rightTriangle:
            let a = x("a"), b = x("b")
            let c = hypot(a, b)
            r = ShapeResult(area: a * b / 2, perimeter: a + b + c,
                            extras: [ShapeExtra(name: "Hypotenuse", symbol: "c", value: c),
                                     ShapeExtra(name: "Angle opposite a", symbol: "α", value: atan2(a, b) * 180 / .pi, kind: .angle)])

        case .circle:
            let rad = measure == .radius ? x("r") : x("d") / 2
            r = ShapeResult(area: .pi * rad * rad, perimeter: 2 * .pi * rad,
                            extras: [measure == .radius
                                     ? ShapeExtra(name: "Diameter", symbol: "d", value: 2 * rad)
                                     : ShapeExtra(name: "Radius", symbol: "r", value: rad)])

        case .semicircle:
            let rad = measure == .radius ? x("r") : x("d") / 2
            r = ShapeResult(area: .pi * rad * rad / 2, perimeter: .pi * rad + 2 * rad,
                            extras: [ShapeExtra(name: "Arc length", symbol: "s", value: .pi * rad)])

        case .sector:
            let rad = x("r"), theta = x("θ")
            guard theta < 360 else {
                return .failure(.outOfRange("Angle θ must be less than 360°. A full turn is a circle."))
            }
            let arc = theta / 360 * 2 * .pi * rad
            r = ShapeResult(area: theta / 360 * .pi * rad * rad, perimeter: 2 * rad + arc,
                            extras: [ShapeExtra(name: "Arc length", symbol: "s", value: arc),
                                     ShapeExtra(name: "Chord", symbol: "c", value: 2 * rad * sin(theta * .pi / 360))])

        case .ring:
            let outer = x("R"), inner = x("r")
            guard inner < outer else {
                return .failure(.impossible("Inner radius r must be smaller than outer radius R."))
            }
            // (R − r)(R + r) keeps precision when the radii are close.
            r = ShapeResult(area: .pi * (outer - inner) * (outer + inner), perimeter: 2 * .pi * (outer + inner),
                            perimeterNote: "Outer and inner edges added together.",
                            extras: [ShapeExtra(name: "Outer circumference", symbol: "C₁", value: 2 * .pi * outer),
                                     ShapeExtra(name: "Inner circumference", symbol: "C₂", value: 2 * .pi * inner),
                                     ShapeExtra(name: "Ring width", symbol: "w", value: outer - inner)])

        case .ellipse:
            let a = x("a"), b = x("b")
            r = ShapeResult(area: .pi * a * b, perimeter: Self.ramanujanII(a, b), perimeterIsApproximate: true,
                            perimeterNote: "Ramanujan's second approximation, accurate to a few parts per billion for most ellipses.")

        case .trapezoid:
            let a = x("a"), b = x("b"), h = x("h")
            r = ShapeResult(area: (a + b) / 2 * h, perimeter: nil)
            let c = values["c"], d = values["d"]
            switch (c, d) {
            case (nil, nil):
                r.perimeterNote = "Add legs c and d for the perimeter."
            case (nil, _), (_, nil):
                r.perimeterNote = "Add both legs c and d for the perimeter."
            case let (c?, d?):
                if c < h { return .failure(.impossible("Leg c can't be shorter than the height h.")) }
                if d < h { return .failure(.impossible("Leg d can't be shorter than the height h.")) }
                r.perimeter = a + b + c + d
                if !Self.trapezoidFits(a: a, b: b, h: h, c: c, d: d) {
                    r.notes.append("These legs don't quite fit a, b and h. Check the measurements.")
                }
            }

        case .parallelogram:
            let b = x("b"), s = x("s"), h = x("h")
            guard h <= s else {
                return .failure(.impossible("Height h can't be more than side s."))
            }
            r = ShapeResult(area: b * h, perimeter: 2 * (b + s),
                            extras: [ShapeExtra(name: "Acute angle", symbol: "α", value: asin(h / s) * 180 / .pi, kind: .angle)])

        case .rhombus:
            let d1 = x("d₁"), d2 = x("d₂")
            let side = hypot(d1 / 2, d2 / 2)
            r = ShapeResult(area: d1 * d2 / 2, perimeter: 4 * side,
                            extras: [ShapeExtra(name: "Side", symbol: "s", value: side)])

        case .regularPolygon:
            let n = x("n"), s = x("s")
            guard n >= 3 else { return .failure(.outOfRange("A polygon needs at least 3 sides.")) }
            guard n <= 1000 else { return .failure(.outOfRange("Use at most 1,000 sides.")) }
            let t = tan(.pi / n)
            r = ShapeResult(area: n * s * s / (4 * t), perimeter: n * s,
                            extras: [ShapeExtra(name: "Apothem", symbol: "aₚ", value: s / (2 * t)),
                                     ShapeExtra(name: "Circumradius", symbol: "R", value: s / (2 * sin(.pi / n))),
                                     ShapeExtra(name: "Interior angle", symbol: "β", value: (n - 2) * 180 / n, kind: .angle)])
        }

        guard r.area.isFinite, r.area > 0, r.perimeter.map({ $0.isFinite }) ?? true else {
            return .failure(.outOfRange("These values are too large or too small to calculate."))
        }
        return .success(r)
    }

    // MARK: Helpers

    /// Heron's formula in the numerically stable form (sides sorted a ≥ b ≥ c). Nil when the sides
    /// break the triangle inequality or make a degenerate (flat) triangle.
    static func heron(_ a: Double, _ b: Double, _ c: Double) -> Double? {
        let s = [a, b, c].sorted(by: >)
        let (x, y, z) = (s[0], s[1], s[2])
        guard x < y + z else { return nil }
        let p = (x + (y + z)) * (z - (x - y)) * (z + (x - y)) * (x + (y - z))
        guard p > 0 else { return nil }
        return p.squareRoot() / 4
    }

    /// Ramanujan's second approximation for an ellipse with semi-axes a and b.
    static func ramanujanII(_ a: Double, _ b: Double) -> Double {
        let l = pow((a - b) / (a + b), 2)
        return .pi * (a + b) * (1 + 3 * l / (10 + (4 - 3 * l).squareRoot()))
    }

    /// Whether legs c and d can join parallel sides a and b at height h (within 1 % of the longer side).
    static func trapezoidFits(a: Double, b: Double, h: Double, c: Double, d: Double) -> Bool {
        let pc = max(0, c * c - h * h).squareRoot()
        let pd = max(0, d * d - h * h).squareRoot()
        let gap = abs(a - b)
        let tol = 0.01 * max(a, b)
        return abs(pc + pd - gap) <= tol || abs(abs(pc - pd) - gap) <= tol
    }
}

// MARK: - Parsing and formatting

enum ShapeNumber {
    /// Accepts "12", "12.5", "12,5", ".5" and surrounding spaces. Nil for empty or anything else.
    static func parse(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard !t.isEmpty, parts.count <= 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.contains(where: { !$0.isEmpty }),
              let v = Double((parts[0].isEmpty ? "0" : String(parts[0])) + "." + (parts.count == 2 && !parts[1].isEmpty ? String(parts[1]) : "0")),
              v.isFinite else { return nil }
        return v
    }

    /// Keeps digits and one decimal separator ("." or ","), at most 9 integer and 6 decimal digits.
    static func sanitize(_ s: String) -> String {
        var out = ""
        var seenSep = false
        var intDigits = 0, fracDigits = 0
        for ch in s {
            if ch.isASCII, ch.isNumber {
                if seenSep { guard fracDigits < 6 else { continue }; fracDigits += 1 }
                else { guard intDigits < 9 else { continue }; intDigits += 1 }
                out.append(ch)
            } else if ch == "." || ch == ",", !seenSep {
                seenSep = true
                out.append(ch)
            }
        }
        return out
    }

    /// Input as typed, shown with a decimal point ("4,2" -> "4.2", ".5" -> "0.5").
    static func echo(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.hasPrefix(".") { t = "0" + t }
        if t.hasSuffix(".") { t.removeLast() }
        return t.isEmpty ? "0" : t
    }

    /// Up to `significant` significant digits, en_AU grouping, no trailing zeros.
    /// Scientific ("1.23×10⁻⁷") below 1e-4 and from 1e12 up.
    static func format(_ v: Double, significant: Int = 6) -> String {
        guard v.isFinite else { return "—" }
        if v == 0 { return "0" }
        let sig = max(1, min(15, significant))
        let mag = abs(v)
        if mag < 1e-4 || mag >= 1e12 {
            let parts = String(format: "%.\(sig - 1)e", v).split(separator: "e")
            guard parts.count == 2, let exp = Int(parts[1]) else { return "—" }
            var mantissa = String(parts[0])
            if mantissa.contains(".") {
                while mantissa.hasSuffix("0") { mantissa.removeLast() }
                if mantissa.hasSuffix(".") { mantissa.removeLast() }
            }
            return "\(mantissa)×10" + superscript(exp)
        }
        let rounded = Double(String(format: "%.\(sig - 1)e", v)) ?? v
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.maximumSignificantDigits = sig
        f.usesSignificantDigits = true
        return f.string(from: NSNumber(value: rounded)) ?? "—"
    }

    static func superscript(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
                                           "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).map { map[$0] ?? $0 })
    }
}
