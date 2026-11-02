//
//  UnitCatalog.swift
//  Plumb
//
//  Every unit the converter offers, with its factor to the SI base unit of its category.
//  Factors are the exact definitions (or are derived arithmetically from exact definitions)
//  published in NIST SP 811 Appendix B, NIST Handbook 44 Appendix C and the BIPM SI Brochure.
//  Nothing here is rounded by hand: where a unit is defined from others, the factor is written
//  as that arithmetic so Double carries full precision. Foundation-only so it can be verified
//  standalone (see the converter check script).
//

import Foundation

/// How a unit maps to its category's base unit.
enum UnitKind: Hashable {
    /// base = value × factor
    case linear(Double)
    /// base = value × scale + offset (temperatures, base kelvin)
    case affine(scale: Double, offset: Double)
    /// base = constant ÷ value (L/100 km, base km/L)
    case reciprocal(Double)
}

struct UnitDef: Identifiable, Hashable {
    let id: String
    let symbol: String
    let name: String
    let kind: UnitKind
    /// True when the factor is exact by definition (or derived only from exact definitions).
    let exact: Bool

    init(_ id: String, _ symbol: String, _ name: String, _ kind: UnitKind, exact: Bool = true) {
        self.id = id; self.symbol = symbol; self.name = name; self.kind = kind; self.exact = exact
    }

    func toBase(_ v: Double) -> Double? {
        switch kind {
        case .linear(let f): return v * f
        case .affine(let s, let o): return v * s + o
        case .reciprocal(let k): return v == 0 ? nil : k / v
        }
    }

    func fromBase(_ b: Double) -> Double? {
        switch kind {
        case .linear(let f): return b / f
        case .affine(let s, let o): return (b - o) / s
        case .reciprocal(let k): return b == 0 ? nil : k / b
        }
    }
}

// MARK: - Exact defining constants

enum UnitConstants {
    // Length (international yard and pound agreement, 1959; NIST SP 811 B.9)
    static let inch = 0.0254
    static let foot = 0.3048
    static let yard = 0.9144
    static let mile = 1609.344
    static let nauticalMile = 1852.0
    // Mass
    static let pound = 0.45359237
    // Volume
    static let usGallon = 231 * inch * inch * inch          // 231 in³ = 3.785411784 L
    static let ukGallon = 4.54609e-3                        // UK Weights and Measures Act 1985
    // Standard gravity and force
    static let gn = 9.80665
    static let poundForce = pound * gn                      // 4.4482216152605 N
    // Energy
    static let calorieIT = 4.1868
    static let calorieTh = 4.184
    /// cal(IT)/(g·K) × 453.59237 g × 5/9 K = 1055.05585262 J (exact by definition)
    static let btuIT = calorieIT * (pound * 1000) * 5.0 / 9.0
    static let footPoundForce = foot * poundForce           // 1.3558179483314004 J
    static let electronVolt = 1.602176634e-19                // SI 2019, exact
    // Pressure (conventional values)
    static let mmHg = 13595.1 * gn / 1000                   // 133.322387415 Pa
    static let mmH2O = gn                                   // 9.80665 Pa (conventional, 1000 kg/m³)
}

// MARK: - Categories

enum UnitCategory: String, CaseIterable, Identifiable, Hashable {
    case length, area, volume, weight, pressure, angle, power, force, work, temperature, speed, time, fuel, voltage, data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: "Work & Energy"
        default: rawValue.capitalized
        }
    }

    var subtitle: String {
        switch self {
        case .length: "Metric, imperial, nautical"
        case .area: "Floors, land, sites"
        case .volume: "Liquids, concrete, tanks"
        case .weight: "Mass, materials, loads"
        case .pressure: "Tyres, gas, hydraulics"
        case .angle: "Degrees, radians, gradians"
        case .power: "Motors, heating, HVAC"
        case .force: "Loads and thrust"
        case .work: "Energy, heat, electricity"
        case .temperature: "°C, °F, K, °R"
        case .speed: "Road, wind, sea"
        case .time: "Seconds to years"
        case .fuel: "Economy and consumption"
        case .voltage: "Electrical potential"
        case .data: "Storage and transfer"
        }
    }

    /// The SI (or reference) base unit the factors map to.
    var baseSymbol: String {
        switch self {
        case .length: "m"
        case .area: "m²"
        case .volume: "m³"
        case .weight: "kg"
        case .pressure: "Pa"
        case .angle: "rad"
        case .power: "W"
        case .force: "N"
        case .work: "J"
        case .temperature: "K"
        case .speed: "m/s"
        case .time: "s"
        case .fuel: "km/L"
        case .voltage: "V"
        case .data: "B"
        }
    }

    var units: [UnitDef] {
        let C = UnitConstants.self
        switch self {
        case .length:
            return [
                UnitDef("nm", "nm", "Nanometre", .linear(1e-9)),
                UnitDef("um", "µm", "Micrometre", .linear(1e-6)),
                UnitDef("mm", "mm", "Millimetre", .linear(1e-3)),
                UnitDef("cm", "cm", "Centimetre", .linear(1e-2)),
                UnitDef("dm", "dm", "Decimetre", .linear(1e-1)),
                UnitDef("m", "m", "Metre", .linear(1)),
                UnitDef("dam", "dam", "Decametre", .linear(10)),
                UnitDef("hm", "hm", "Hectometre", .linear(100)),
                UnitDef("km", "km", "Kilometre", .linear(1000)),
                UnitDef("thou", "mil", "Thou (mil)", .linear(C.inch / 1000)),
                UnitDef("in", "in", "Inch", .linear(C.inch)),
                UnitDef("ft", "ft", "Foot", .linear(C.foot)),
                UnitDef("yd", "yd", "Yard", .linear(C.yard)),
                UnitDef("fathom", "ftm", "Fathom", .linear(6 * C.foot)),
                UnitDef("chain", "ch", "Chain", .linear(66 * C.foot)),
                UnitDef("furlong", "fur", "Furlong", .linear(660 * C.foot)),
                UnitDef("mi", "mi", "Mile", .linear(C.mile)),
                UnitDef("league", "lea", "League (3 mi)", .linear(3 * C.mile)),
                UnitDef("nmi", "nmi", "Nautical mile", .linear(C.nauticalMile)),
                UnitDef("angstrom", "Å", "Ångström", .linear(1e-10)),
            ]
        case .area:
            let sq = { (f: Double) in f * f }
            return [
                UnitDef("mm2", "mm²", "Square millimetre", .linear(1e-6)),
                UnitDef("cm2", "cm²", "Square centimetre", .linear(1e-4)),
                UnitDef("m2", "m²", "Square metre", .linear(1)),
                UnitDef("are", "a", "Are", .linear(100)),
                UnitDef("ha", "ha", "Hectare", .linear(1e4)),
                UnitDef("km2", "km²", "Square kilometre", .linear(1e6)),
                UnitDef("in2", "in²", "Square inch", .linear(sq(C.inch))),
                UnitDef("ft2", "ft²", "Square foot", .linear(sq(C.foot))),
                UnitDef("yd2", "yd²", "Square yard", .linear(sq(C.yard))),
                UnitDef("acre", "ac", "Acre", .linear(4840 * sq(C.yard))),
                UnitDef("mi2", "mi²", "Square mile", .linear(sq(C.mile))),
            ]
        case .volume:
            let cube = { (f: Double) in f * f * f }
            let usFlOz = C.usGallon / 128
            return [
                UnitDef("mm3", "mm³", "Cubic millimetre", .linear(1e-9)),
                UnitDef("cm3", "cm³", "Cubic centimetre", .linear(1e-6)),
                UnitDef("mL", "mL", "Millilitre", .linear(1e-6)),
                UnitDef("cL", "cL", "Centilitre", .linear(1e-5)),
                UnitDef("dL", "dL", "Decilitre", .linear(1e-4)),
                UnitDef("L", "L", "Litre", .linear(1e-3)),
                UnitDef("dm3", "dm³", "Cubic decimetre", .linear(1e-3)),
                UnitDef("m3", "m³", "Cubic metre", .linear(1)),
                UnitDef("in3", "in³", "Cubic inch", .linear(cube(C.inch))),
                UnitDef("ft3", "ft³", "Cubic foot", .linear(cube(C.foot))),
                UnitDef("yd3", "yd³", "Cubic yard", .linear(cube(C.yard))),
                UnitDef("usTsp", "tsp (US)", "Teaspoon (US)", .linear(usFlOz / 6)),
                UnitDef("usTbsp", "tbsp (US)", "Tablespoon (US)", .linear(usFlOz / 2)),
                UnitDef("usFlOz", "fl oz (US)", "Fluid ounce (US)", .linear(usFlOz)),
                UnitDef("usCup", "cup (US)", "Cup (US customary)", .linear(usFlOz * 8)),
                UnitDef("usPt", "pt (US)", "Pint (US liquid)", .linear(C.usGallon / 8)),
                UnitDef("usQt", "qt (US)", "Quart (US liquid)", .linear(C.usGallon / 4)),
                UnitDef("usGal", "gal (US)", "Gallon (US)", .linear(C.usGallon)),
                UnitDef("ukFlOz", "fl oz (UK)", "Fluid ounce (UK)", .linear(C.ukGallon / 160)),
                UnitDef("ukPt", "pt (UK)", "Pint (UK)", .linear(C.ukGallon / 8)),
                UnitDef("ukGal", "gal (UK)", "Gallon (UK)", .linear(C.ukGallon)),
                UnitDef("bbl", "bbl", "Barrel (oil, 42 US gal)", .linear(42 * C.usGallon)),
                UnitDef("acreFt", "ac·ft", "Acre-foot", .linear(43560 * cube(C.foot))),
            ]
        case .weight:
            return [
                UnitDef("mg", "mg", "Milligram", .linear(1e-6)),
                UnitDef("g", "g", "Gram", .linear(1e-3)),
                UnitDef("kg", "kg", "Kilogram", .linear(1)),
                UnitDef("t", "t", "Tonne", .linear(1000)),
                UnitDef("ct", "ct", "Carat (metric)", .linear(2e-4)),
                UnitDef("gr", "gr", "Grain", .linear(C.pound / 7000)),
                UnitDef("oz", "oz", "Ounce", .linear(C.pound / 16)),
                UnitDef("ozt", "oz t", "Troy ounce", .linear(480 * C.pound / 7000)),
                UnitDef("lb", "lb", "Pound", .linear(C.pound)),
                UnitDef("st", "st", "Stone", .linear(14 * C.pound)),
                UnitDef("shortTon", "ton (US)", "Short ton", .linear(2000 * C.pound)),
                UnitDef("longTon", "ton (UK)", "Long ton", .linear(2240 * C.pound)),
            ]
        case .pressure:
            let psi = C.poundForce / (C.inch * C.inch)
            return [
                UnitDef("Pa", "Pa", "Pascal", .linear(1)),
                UnitDef("hPa", "hPa", "Hectopascal", .linear(100)),
                UnitDef("kPa", "kPa", "Kilopascal", .linear(1e3)),
                UnitDef("MPa", "MPa", "Megapascal", .linear(1e6)),
                UnitDef("Nmm2", "N/mm²", "Newton per mm²", .linear(1e6)),
                UnitDef("mbar", "mbar", "Millibar", .linear(100)),
                UnitDef("bar", "bar", "Bar", .linear(1e5)),
                UnitDef("atm", "atm", "Standard atmosphere", .linear(101_325)),
                UnitDef("at", "at", "Technical atmosphere (kgf/cm²)", .linear(C.gn * 1e4)),
                UnitDef("psi", "psi", "Pound per square inch", .linear(psi)),
                UnitDef("ksi", "ksi", "Kip per square inch", .linear(psi * 1000)),
                UnitDef("torr", "Torr", "Torr", .linear(101_325.0 / 760)),
                UnitDef("mmHg", "mmHg", "Millimetre of mercury", .linear(C.mmHg)),
                UnitDef("inHg", "inHg", "Inch of mercury", .linear(C.mmHg * 25.4)),
                UnitDef("mmH2O", "mmH₂O", "Millimetre of water", .linear(C.mmH2O)),
                UnitDef("inH2O", "inH₂O", "Inch of water", .linear(C.mmH2O * 25.4)),
            ]
        case .angle:
            return [
                UnitDef("deg", "°", "Degree", .linear(Double.pi / 180)),
                UnitDef("arcmin", "′", "Arcminute", .linear(Double.pi / 10_800)),
                UnitDef("arcsec", "″", "Arcsecond", .linear(Double.pi / 648_000)),
                UnitDef("rad", "rad", "Radian", .linear(1)),
                UnitDef("mrad", "mrad", "Milliradian", .linear(1e-3)),
                UnitDef("grad", "gon", "Gradian", .linear(Double.pi / 200)),
                UnitDef("mil", "mil", "Mil (NATO, 6400/turn)", .linear(2 * Double.pi / 6400)),
                UnitDef("turn", "rev", "Revolution", .linear(2 * Double.pi)),
            ]
        case .power:
            return [
                UnitDef("W", "W", "Watt", .linear(1)),
                UnitDef("kW", "kW", "Kilowatt", .linear(1e3)),
                UnitDef("MW", "MW", "Megawatt", .linear(1e6)),
                UnitDef("hp", "hp", "Horsepower (mechanical)", .linear(550 * C.footPoundForce)),
                UnitDef("PS", "PS", "Horsepower (metric)", .linear(75 * C.gn)),
                UnitDef("hpE", "hp(E)", "Horsepower (electric)", .linear(746)),
                UnitDef("ftlbfs", "ft·lbf/s", "Foot-pound-force per second", .linear(C.footPoundForce)),
                UnitDef("btuh", "BTU/h", "BTU (IT) per hour", .linear(C.btuIT / 3600)),
                UnitDef("kcalh", "kcal/h", "Kilocalorie (IT) per hour", .linear(C.calorieIT * 1000 / 3600)),
                UnitDef("TR", "TR", "Ton of refrigeration", .linear(12_000 * C.btuIT / 3600)),
            ]
        case .force:
            return [
                UnitDef("N", "N", "Newton", .linear(1)),
                UnitDef("kN", "kN", "Kilonewton", .linear(1e3)),
                UnitDef("MN", "MN", "Meganewton", .linear(1e6)),
                UnitDef("dyn", "dyn", "Dyne", .linear(1e-5)),
                UnitDef("kgf", "kgf", "Kilogram-force", .linear(C.gn)),
                UnitDef("tf", "tf", "Tonne-force", .linear(1000 * C.gn)),
                UnitDef("lbf", "lbf", "Pound-force", .linear(C.poundForce)),
                UnitDef("kip", "kip", "Kip", .linear(1000 * C.poundForce)),
                UnitDef("pdl", "pdl", "Poundal", .linear(C.pound * C.foot)),
            ]
        case .work:
            return [
                UnitDef("J", "J", "Joule", .linear(1)),
                UnitDef("kJ", "kJ", "Kilojoule", .linear(1e3)),
                UnitDef("MJ", "MJ", "Megajoule", .linear(1e6)),
                UnitDef("Wh", "Wh", "Watt-hour", .linear(3600)),
                UnitDef("kWh", "kWh", "Kilowatt-hour", .linear(3.6e6)),
                UnitDef("cal", "cal", "Calorie (IT)", .linear(C.calorieIT)),
                UnitDef("kcal", "kcal", "Kilocalorie (IT)", .linear(C.calorieIT * 1000)),
                UnitDef("calth", "cal(th)", "Calorie (thermochemical)", .linear(C.calorieTh)),
                UnitDef("btu", "BTU", "British thermal unit (IT)", .linear(C.btuIT)),
                UnitDef("thermUS", "thm (US)", "Therm (US)", .linear(1.054804e8)),
                UnitDef("thermEC", "thm (EC)", "Therm (EC)", .linear(1.05506e8)),
                UnitDef("ftlbf", "ft·lbf", "Foot-pound-force", .linear(C.footPoundForce)),
                UnitDef("Nm", "N·m", "Newton-metre", .linear(1)),
                UnitDef("eV", "eV", "Electronvolt", .linear(C.electronVolt)),
                UnitDef("erg", "erg", "Erg", .linear(1e-7)),
            ]
        case .temperature:
            return [
                UnitDef("C", "°C", "Celsius", .affine(scale: 1, offset: 273.15)),
                UnitDef("F", "°F", "Fahrenheit", .affine(scale: 5.0 / 9.0, offset: 459.67 * 5.0 / 9.0)),
                UnitDef("K", "K", "Kelvin", .affine(scale: 1, offset: 0)),
                UnitDef("R", "°R", "Rankine", .affine(scale: 5.0 / 9.0, offset: 0)),
            ]
        case .speed:
            return [
                UnitDef("mps", "m/s", "Metre per second", .linear(1)),
                UnitDef("kmh", "km/h", "Kilometre per hour", .linear(1000.0 / 3600)),
                UnitDef("mph", "mph", "Mile per hour", .linear(C.mile / 3600)),
                UnitDef("kn", "kn", "Knot", .linear(C.nauticalMile / 3600)),
                UnitDef("fps", "ft/s", "Foot per second", .linear(C.foot)),
                UnitDef("fpm", "ft/min", "Foot per minute", .linear(C.foot / 60)),
            ]
        case .time:
            return [
                UnitDef("ns", "ns", "Nanosecond", .linear(1e-9)),
                UnitDef("us", "µs", "Microsecond", .linear(1e-6)),
                UnitDef("ms", "ms", "Millisecond", .linear(1e-3)),
                UnitDef("s", "s", "Second", .linear(1)),
                UnitDef("min", "min", "Minute", .linear(60)),
                UnitDef("h", "h", "Hour", .linear(3600)),
                UnitDef("d", "d", "Day", .linear(86_400)),
                UnitDef("wk", "wk", "Week", .linear(604_800)),
                UnitDef("yr", "yr", "Year (365 days)", .linear(365 * 86_400)),
                UnitDef("yrJ", "a", "Julian year (365.25 days)", .linear(365.25 * 86_400)),
            ]
        case .fuel:
            let km = 1.0, mileKm = C.mile / 1000
            let usGalL = C.usGallon * 1000, ukGalL = C.ukGallon * 1000
            return [
                UnitDef("kmL", "km/L", "Kilometres per litre", .linear(km)),
                UnitDef("L100", "L/100 km", "Litres per 100 km", .reciprocal(100)),
                UnitDef("mpgUS", "mpg (US)", "Miles per US gallon", .linear(mileKm / usGalL)),
                UnitDef("mpgUK", "mpg (UK)", "Miles per UK gallon", .linear(mileKm / ukGalL)),
            ]
        case .voltage:
            return [
                UnitDef("uV", "µV", "Microvolt", .linear(1e-6)),
                UnitDef("mV", "mV", "Millivolt", .linear(1e-3)),
                UnitDef("V", "V", "Volt", .linear(1)),
                UnitDef("kV", "kV", "Kilovolt", .linear(1e3)),
                UnitDef("MV", "MV", "Megavolt", .linear(1e6)),
            ]
        case .data:
            return [
                UnitDef("bit", "bit", "Bit", .linear(0.125)),
                UnitDef("kbit", "kbit", "Kilobit", .linear(125)),
                UnitDef("Mbit", "Mbit", "Megabit", .linear(125e3)),
                UnitDef("Gbit", "Gbit", "Gigabit", .linear(125e6)),
                UnitDef("B", "B", "Byte", .linear(1)),
                UnitDef("kB", "kB", "Kilobyte (1000 B)", .linear(1e3)),
                UnitDef("MB", "MB", "Megabyte", .linear(1e6)),
                UnitDef("GB", "GB", "Gigabyte", .linear(1e9)),
                UnitDef("TB", "TB", "Terabyte", .linear(1e12)),
                UnitDef("PB", "PB", "Petabyte", .linear(1e15)),
                UnitDef("KiB", "KiB", "Kibibyte (1024 B)", .linear(1024)),
                UnitDef("MiB", "MiB", "Mebibyte", .linear(1_048_576)),
                UnitDef("GiB", "GiB", "Gibibyte", .linear(1_073_741_824)),
                UnitDef("TiB", "TiB", "Tebibyte", .linear(1_099_511_627_776)),
                UnitDef("PiB", "PiB", "Pebibyte", .linear(1_125_899_906_842_624)),
            ]
        }
    }

    /// Sensible starting pair (from, to).
    var defaultPair: (from: String, to: String) {
        switch self {
        case .length: ("m", "ft")
        case .area: ("m2", "ft2")
        case .volume: ("m3", "L")
        case .weight: ("kg", "lb")
        case .pressure: ("bar", "psi")
        case .angle: ("deg", "rad")
        case .power: ("kW", "hp")
        case .force: ("kN", "lbf")
        case .work: ("kWh", "MJ")
        case .temperature: ("C", "F")
        case .speed: ("kmh", "mph")
        case .time: ("h", "min")
        case .fuel: ("L100", "mpgUS")
        case .voltage: ("V", "mV")
        case .data: ("GB", "GiB")
        }
    }

    /// Temperatures can go negative; everything else here is a magnitude.
    var allowsNegative: Bool { self == .temperature }

    /// One line shown under the results: where the factors come from.
    var sourceNote: String {
        switch self {
        case .temperature: "Exact: K = °C + 273.15, °F = °C × 9/5 + 32, °R = K × 9/5."
        case .fuel: "From exact mile, US gallon (231 in³) and UK gallon (4.54609 L). L/100 km is reciprocal."
        case .data: "SI prefixes are powers of 1000 (kB); IEC binary prefixes are powers of 1024 (KiB)."
        case .pressure: "Exact definitions; mmHg, inHg and inH₂O are the conventional values (NIST SP 811)."
        case .work: "Calorie is the International Table value (4.1868 J); thermochemical listed separately."
        case .time: "Year is 365 days (NIST SP 811); the Julian year is 365.25 days."
        default: "Exact definitions (NIST SP 811, Handbook 44, SI Brochure)."
        }
    }

    func unit(_ id: String) -> UnitDef? { units.first { $0.id == id } }

    /// Converts `value` from one unit to another in this category. Nil when undefined (e.g. 0 L/100 km).
    static func convert(_ value: Double, from: UnitDef, to: UnitDef) -> Double? {
        guard value.isFinite, let base = from.toBase(value), base.isFinite else { return nil }
        guard let out = to.fromBase(base), out.isFinite else { return nil }
        return out
    }
}
