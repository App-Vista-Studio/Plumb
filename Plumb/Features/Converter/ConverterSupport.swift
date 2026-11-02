//
//  ConverterSupport.swift
//  Plumb
//
//  Non-numeric helpers for the Unit Converter: result formatting, keypad input rules and
//  VoiceOver wording. Foundation-only so the formatter can be checked standalone next to
//  UnitCatalog.swift. No conversion factors live here.
//

import Foundation

// MARK: - Number formatting

/// Formats converted values: precise and readable.
/// - Binary float noise is removed first (rounded to at most 12 significant digits).
/// - Up to 10 significant digits are shown (more only for whole numbers, which are exact).
/// - Thousands are grouped (en_AU), trailing zeros are trimmed.
/// - Scientific notation (×10ⁿ) when |x| < 10⁻⁶ or |x| ≥ 10¹⁵.
nonisolated enum ConverterFormat {
    static let placeholder = "—"
    static let groupingSeparator = Locale(identifier: "en_AU").groupingSeparator ?? ","

    static func format(_ x: Double) -> String {
        guard x.isFinite else { return placeholder }
        if x == 0 { return "0" }
        let a = abs(x)
        // Whole numbers below 10¹⁵ are exact in Double: every digit is shown (1 GiB = 1,073,741,824 B).
        if a >= 1, a < 1e15, let r15 = rounded(x, significant: 15), r15 == r15.rounded() {
            return (r15 < 0 ? "-" : "") + group(String(format: "%.0f", abs(r15)))
        }
        guard let r12 = rounded(x, significant: 12), let r15 = rounded(x, significant: 15) else { return placeholder }
        // A value that is already a short decimal (≤ 12 significant digits once float noise is gone) is
        // shown in full, so exact results stay exact (1 acre = 4,046.8564224 m²). Anything longer gets 10.
        let terminates = r12 == r15
        if a < 1e-6 || a >= 1e15 { return scientific(r12, significant: terminates ? 12 : 10) }
        // Never end a large value in invented zeros: keep every integer digit.
        let integerDigits = a >= 1 ? Int(log10(a).rounded(.down)) + 1 : 1
        if integerDigits > 12 { return plain(x, significant: integerDigits) }
        return plain(r12, significant: terminates ? 12 : max(10, integerDigits))
    }

    /// `x` rounded to `significant` digits through its decimal representation.
    static func rounded(_ x: Double, significant: Int) -> Double? {
        Double(String(format: "%.\(significant - 1)e", x))
    }

    /// Plain decimal with grouping, built from the decimal digits so no new float error is introduced.
    static func plain(_ x: Double, significant: Int) -> String {
        guard let (digits, exp) = decimalDigits(abs(x), significant: significant) else { return placeholder }
        var intPart: String
        var frac: String
        if exp >= 0 {
            let n = exp + 1
            if digits.count >= n {
                intPart = String(digits.prefix(n))
                frac = String(digits.dropFirst(n))
            } else {
                intPart = digits + String(repeating: "0", count: n - digits.count)
                frac = ""
            }
        } else {
            intPart = "0"
            frac = String(repeating: "0", count: -exp - 1) + digits
        }
        while frac.hasSuffix("0") { frac.removeLast() }
        if intPart.isEmpty { intPart = "0" }
        let body = group(intPart) + (frac.isEmpty ? "" : "." + frac)
        return (x < 0 && body != "0" ? "-" : "") + body
    }

    /// "1.23×10⁻⁷" with trailing zeros trimmed from the mantissa.
    static func scientific(_ x: Double, significant: Int) -> String {
        let parts = String(format: "%.\(significant - 1)e", x).split(separator: "e")
        guard parts.count == 2, let exp = Int(parts[1]) else { return placeholder }
        var mantissa = String(parts[0])
        if mantissa.contains(".") {
            while mantissa.hasSuffix("0") { mantissa.removeLast() }
            if mantissa.hasSuffix(".") { mantissa.removeLast() }
        }
        return mantissa + "×10" + superscript(exp)
    }

    /// Digit string (no point) and decimal exponent of the leading digit, e.g. 1609.344 → ("1609344", 3).
    private static func decimalDigits(_ a: Double, significant: Int) -> (String, Int)? {
        let parts = String(format: "%.\(significant - 1)e", a).split(separator: "e")
        guard parts.count == 2, let exp = Int(parts[1]) else { return nil }
        return (parts[0].filter { $0 != "." }, exp)
    }

    /// Inserts the grouping separator every three digits from the right.
    static func group(_ intDigits: String) -> String {
        var out = ""
        for (i, ch) in intDigits.enumerated() {
            if i > 0, (intDigits.count - i) % 3 == 0 { out += groupingSeparator }
            out.append(ch)
        }
        return out
    }

    static func superscript(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
                                           "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).compactMap { map[$0] })
    }

    /// The keypad string as shown in the FROM panel: integer part grouped, the rest exactly as typed.
    static func input(_ raw: String) -> String {
        let negative = raw.hasPrefix("-")
        let body = negative ? String(raw.dropFirst()) : raw
        let pieces = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var out = group(String(pieces.first ?? "0"))
        if pieces.count == 2 { out += "." + pieces[1] }
        return (negative ? "-" : "") + out
    }

    /// The value as the keypad could have typed it (ungrouped, ≤ 10 digits, no exponent), or nil.
    static func typable(_ x: Double, allowsNegative: Bool) -> String? {
        let s = format(x).replacingOccurrences(of: groupingSeparator, with: "")
        guard s != placeholder, !s.contains("×") else { return nil }
        if s.hasPrefix("-") && !allowsNegative { return nil }
        guard s.filter(\.isNumber).count <= ConverterInput.maxDigits else { return nil }
        return ConverterInput.sanitise(s, allowsNegative: allowsNegative)
    }
}

// MARK: - Keypad input

/// Keypad editing rules: one decimal point, no leading zeros, 10 characters, optional leading minus.
nonisolated enum ConverterInput {
    static let maxDigits = 10

    static func press(_ key: String, on current: String, allowsNegative: Bool = false) -> String {
        var negative = allowsNegative && current.hasPrefix("-")
        var s = current.hasPrefix("-") ? String(current.dropFirst()) : current
        switch key {
        case "C": return "0"
        case "±":
            guard allowsNegative else { return current }
            negative.toggle()
        case "⌫":
            if s.count > 1 {
                s = String(s.dropLast())
            } else {
                s = "0"
                negative = false
            }
        case ".": if !s.contains(".") { s += "." }
        default:
            guard key.count == 1, key.first?.isASCII == true, key.first?.isNumber == true else { return current }
            s = (s == "0" ? "" : s) + key
        }
        guard s.count <= maxDigits else { return current }
        return (negative ? "-" : "") + s
    }

    /// Keeps digits and the first decimal point (a decimal comma becomes a point), plus a leading minus
    /// when allowed; empty becomes "0".
    static func sanitise(_ raw: String, allowsNegative: Bool = false) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let negative = allowsNegative && (trimmed.hasPrefix("-") || trimmed.hasPrefix("−"))
        var out = ""
        var seenPoint = false
        for ch in trimmed {
            if ch.isASCII, ch.isNumber {
                out.append(ch)
            } else if (ch == "." || ch == ","), !seenPoint {
                seenPoint = true
                out.append(out.isEmpty ? "0." : ".")
            }
        }
        while out.count > 1, out.hasPrefix("0"), !out.hasPrefix("0.") { out.removeFirst() }
        if out.isEmpty { out = "0" }
        return (negative ? "-" : "") + String(out.prefix(maxDigits))
    }

    /// Numeric value of a keypad string ("2." reads as 2, "-0" as 0).
    static func number(_ s: String) -> Double? {
        var t = s
        if t.hasSuffix(".") { t.removeLast() }
        return Double(t)
    }
}

// MARK: - VoiceOver

/// Spoken wording for VoiceOver ("ft" reads as "feet", not "eff tee").
nonisolated enum ConverterSpeech {
    /// The unit's full name, pluralised on its head noun unless `plural` is false.
    /// "Foot per second" → "Feet per second", "Inch of water" → "Inches of water".
    static func unit(name: String, plural: Bool = true) -> String {
        guard plural else { return name }
        var base = name
        var tail = ""
        if let r = name.range(of: " (") {
            base = String(name[..<r.lowerBound])
            tail = String(name[r.lowerBound...])
        }
        for sep in [" per ", " of "] {
            if let r = base.range(of: sep) {
                return pluraliseLastWord(String(base[..<r.lowerBound])) + String(base[r.lowerBound...]) + tail
            }
        }
        return pluraliseLastWord(base) + tail
    }

    /// Plural wording for a number: "1 metre", "2.5 metres".
    static func unit(name: String, for value: Double?) -> String {
        unit(name: name, plural: value.map { abs($0) != 1 } ?? true)
    }

    /// A formatted value as VoiceOver should read it: "1.2×10⁻⁷" → "1.2 times 10 to the power of minus 7".
    static func value(_ s: String) -> String {
        guard s != ConverterFormat.placeholder else { return "no result" }
        guard let r = s.range(of: "×10") else { return s.replacingOccurrences(of: "-", with: "minus ") }
        let mantissa = String(s[..<r.lowerBound]).replacingOccurrences(of: "-", with: "minus ")
        let digits: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5",
                                              "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"]
        var exp = ""
        for ch in s[r.upperBound...] {
            if ch == "⁻" { exp += "minus " } else if let d = digits[ch] { exp.append(d) }
        }
        return "\(mantissa) times 10 to the power of \(exp)"
    }

    private static let invariant: Set<String> = ["celsius", "fahrenheit", "horsepower", "thou", "stone", "hertz"]

    private static func pluraliseLastWord(_ phrase: String) -> String {
        var words = phrase.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let last = words.popLast() else { return phrase }
        // "Kilogram-force" → "Kilograms-force"; "Watt-hour" → "Watt-hours".
        var parts = last.split(separator: "-").map(String.init)
        let idx = parts.count > 1 && parts.last?.lowercased() == "force" ? parts.count - 2 : parts.count - 1
        parts[idx] = pluralWord(parts[idx])
        words.append(parts.joined(separator: "-"))
        return words.joined(separator: " ")
    }

    private static func pluralWord(_ w: String) -> String {
        let lower = w.lowercased()
        if invariant.contains(lower) || lower.hasSuffix("s") { return w }
        if lower == "foot" { return w.first == "F" ? "Feet" : "feet" }
        if lower.hasSuffix("ch") || lower.hasSuffix("x") { return w + "es" }
        return w + "s"
    }
}
