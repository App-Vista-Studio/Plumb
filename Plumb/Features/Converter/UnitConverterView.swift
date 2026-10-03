//
//  UnitConverterView.swift
//  Plumb
//
//  Unit Converter (Converter board). The result keeps the significant figures of the input (3 to 6).
//

import SwiftUI
import UIKit

struct UnitConverterView: View {
    @Environment(Router.self) private var router

    // Last conversion is kept between visits, like the leading unit-converter apps.
    @AppStorage("converter.category") private var categoryRaw = ConverterCategory.length.rawValue
    @AppStorage("converter.value") private var storedValue = "2.43"
    @AppStorage("converter.from") private var storedFrom = "m"
    @AppStorage("converter.to") private var storedTo = "ft"
    @State private var copied = false

    private var category: ConverterCategory { ConverterCategory(rawValue: categoryRaw) ?? .length }
    /// Sanitised input: only digits and one decimal point, at most 10 characters.
    private var value: String { ConverterInput.sanitise(storedValue) }
    private var from: String { category.factors[storedFrom] != nil ? storedFrom : category.defaults.0 }
    private var to: String { category.factors[storedTo] != nil ? storedTo : category.defaults.1 }

    private var result: String {
        guard let v = Double(value), v.isFinite,
              let f = category.factors[from], let t = category.factors[to], t != 0 else { return "—" }
        return ConverterFormat.format(v * f / t, input: value)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("Unit Converter")
                    .font(.pm(17, .bold))
                    .foregroundStyle(PM.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    IconCircleButton(icon: .back, label: "Back to tools", stroke: 2) { router.pop() }
                    Spacer()
                    TopBarPlaceholder()
                }
            }
            .frame(height: 46) // 44 link + 1 px border outside the box on the board

            PMSegmented(
                options: ConverterCategory.allCases.map { ($0, $0.label) },
                selection: Binding(get: { category }, set: pick),
                segmentHeight: 44,
                fontSize: 14,
                fontWeight: .bold,
                tracking: 0,
                fitContent: true,
                trackPadding: 5
            )

            ConverterPanel(title: "FROM", tag: "User-entered", tagColor: PM.Colors.calibrating,
                           fill: PM.Colors.surface, value: value, valueColor: PM.Colors.textPrimary,
                           unit: from, units: category.units, prefix: "From") { storedFrom = $0 }
                .accessibilityHint("Type with the keypad below")

            Button(action: swap) {
                SVGStroke(d: PMIconName.swapVertical.d, size: 18, lineWidth: 2.2)
                    .foregroundStyle(PM.Colors.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(PM.Colors.accent))
                    .overlay(Circle().strokeBorder(PM.Colors.background, lineWidth: 4))
            }
            .buttonStyle(.pmPress)
            .accessibilityLabel("Swap units")
            .padding(.vertical, -22)
            .zIndex(2)

            ConverterPanel(title: "TO", tag: "Calculated", tagColor: PM.Colors.measuring,
                           fill: PM.Colors.surfaceSunken, value: result, valueColor: PM.Colors.accent,
                           unit: to, units: category.units, prefix: "To") { storedTo = $0 }
                .contextMenu {
                    Button("Copy \(result) \(to)", systemImage: "doc.on.doc") { copyResult() }
                        .disabled(result == "—")
                }
                .accessibilityAction(named: "Copy result") { copyResult() }

            Spacer(minLength: 0)

            ConverterKeypad(press: press)
        }
        .padding(.top, 56 + 1 - PM.Board.statusBar)
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
        .ignoresSafeArea(.container, edges: .bottom)
        .background(PM.Colors.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if copied {
                ToastView(text: "Copied")
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
    }

    private func pick(_ c: ConverterCategory) {
        categoryRaw = c.rawValue
        storedFrom = c.defaults.0
        storedTo = c.defaults.1
    }

    private func swap() {
        // A result the keypad can't express (scientific, or longer than 10 characters) keeps the input.
        let plain = result.replacingOccurrences(of: ",", with: "")
        let typable = result != "—" && !plain.contains("×") && plain.count <= 10
        let newValue = typable ? ConverterInput.sanitise(plain) : value
        let (f, t) = (from, to)
        storedFrom = t
        storedTo = f
        storedValue = newValue
        Haptics.selection()
    }

    private func press(_ key: String) {
        storedValue = ConverterInput.press(key, on: value)
    }

    private func copyResult() {
        guard result != "—" else { return }
        UIPasteboard.general.string = "\(result) \(to)"
        Haptics.selection()
        withAnimation(PM.Motion.normal) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(PM.Motion.normal) { copied = false }
        }
    }
}

/// Keypad editing rules from the Converter board: one decimal point, no leading zeros, 10 characters.
enum ConverterInput {
    static func press(_ key: String, on current: String) -> String {
        var s = current
        switch key {
        case "C": return "0"
        case "⌫": s = s.count > 1 ? String(s.dropLast()) : "0"
        case ".": if !s.contains(".") { s += "." }
        default:
            guard key.count == 1, key.first?.isNumber == true else { return current }
            s = (s == "0" ? "" : s) + key
        }
        return s.count <= 10 ? s : current
    }

    /// Keeps digits and the first decimal point (a decimal comma becomes a point); empty becomes "0".
    static func sanitise(_ raw: String) -> String {
        var out = ""
        var seenPoint = false
        for ch in raw {
            if ch.isASCII, ch.isNumber {
                out.append(ch)
            } else if (ch == "." || ch == ","), !seenPoint {
                seenPoint = true
                out.append(out.isEmpty ? "0." : ".")
            }
        }
        while out.count > 1, out.hasPrefix("0"), !out.hasPrefix("0.") { out.removeFirst() }
        if out.isEmpty { out = "0" }
        return String(out.prefix(10))
    }
}

// MARK: - Panel

private struct ConverterPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    private var light: Bool { colorScheme == .light }
    var title: String
    var tag: String
    var tagColor: Color
    var fill: Color
    var value: String
    var valueColor: Color
    var unit: String
    var units: [String]
    var prefix: String
    var onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).pmCaptionStyle()
                Spacer()
                Text(tag).font(.pm(12, .semibold)).foregroundStyle(tagColor)
            }
            // Board renders the value and the 22 px unit with no gap between them.
            (Text(value).font(.pm(44, .light)).foregroundStyle(valueColor)
             + Text(unit).font(.pm(22)).foregroundStyle(PM.Colors.textSecondary))
                .tracking(-1)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title.capitalized), \(value == "—" ? "no result" : value) \(ConverterSpeech.unit(unit))")
                .accessibilityAddTraits(.updatesFrequently)

            // The selected chip is scrolled to the centre so it never sits under the edge fade.
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(units, id: \.self) { u in
                            let on = u == unit
                            Button { onPick(u) } label: {
                                Text(u)
                                    .font(.pm(14, .bold))
                                    .foregroundStyle(on ? PM.Colors.onThumb : PM.Colors.textSecondary)
                                    .padding(.horizontal, 13)
                                    .frame(minWidth: 46)
                                    .frame(height: 44)
                                    .background(Capsule().fill(on ? PM.Colors.thumb : PM.Colors.surfaceRaised))
                                    // Light mode: the white thumb sits on a near-white card, so the accent ring marks the selection.
                                    .overlay(Capsule().strokeBorder(on ? (light ? PM.Colors.accent : PM.Colors.thumb) : PM.Colors.borderStrong,
                                                                    lineWidth: on && light ? 2 : 1))
                                    .shadow(color: .black.opacity(on && light ? 0.08 : 0), radius: 3, y: 1)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .id(u)
                            .accessibilityLabel("\(prefix) \(ConverterSpeech.unit(u))")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    // The row bleeds into the card padding, so the fades sit in that padding at rest.
                    .padding(.leading, 16)
                    .padding(.trailing, 16 + 28)
                }
                .scrollIndicators(.hidden)
                // Soft edge fades: scrolled chips fade out instead of being cut off; the trailing one hints that the row scrolls.
                .mask(
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                        Rectangle().fill(.black)
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 28)
                    }
                )
                .onAppear { proxy.scrollTo(unit, anchor: .center) }
                .onChange(of: unit) { _, u in
                    withAnimation(PM.Motion.normal) { proxy.scrollTo(u, anchor: .center) }
                }
            }
            .padding(.horizontal, -16)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 17)
        .pmCard(fill: fill)
    }
}

/// Spoken unit names for VoiceOver ("ft" reads as "feet", not "eff tee").
enum ConverterSpeech {
    static func unit(_ u: String) -> String {
        switch u {
        case "mm": "millimetres"
        case "cm": "centimetres"
        case "m": "metres"
        case "km": "kilometres"
        case "in": "inches"
        case "ft": "feet"
        case "yd": "yards"
        case "mi": "miles"
        case "°": "degrees"
        case "rad": "radians"
        case "mm²": "square millimetres"
        case "cm²": "square centimetres"
        case "m²": "square metres"
        case "ft²": "square feet"
        case "mL": "millilitres"
        case "L": "litres"
        case "m³": "cubic metres"
        case "ft³": "cubic feet"
        default: u
        }
    }
}

// MARK: - Keypad

private struct ConverterKeypad: View {
    var press: (String) -> Void
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { k in
                Button { press(k) } label: {
                    Text(k)
                        .font(.pm(24))
                        .monospacedDigit()
                        .foregroundStyle(PM.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .pmCard(radius: 18)
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.pmPress)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    if k == "⌫" { press("C"); Haptics.selection() }
                })
                .accessibilityLabel(k == "⌫" ? "Delete" : k == "." ? "Decimal point" : k)
                .accessibilityHint(k == "⌫" ? "Touch and hold to clear" : "")
            }
        }
    }
}

// MARK: - Units

private enum ConverterCategory: String, CaseIterable, Hashable {
    case length, angle, area, volume

    var label: String { rawValue.capitalized }

    /// Units in display order with their factor to the base unit.
    private var table: [(String, Double)] {
        switch self {
        case .length:
            [("mm", 0.001), ("cm", 0.01), ("m", 1), ("km", 1000), ("in", 0.0254), ("ft", 0.3048), ("yd", 0.9144), ("mi", 1609.344)]
        case .angle:
            [("°", Double.pi / 180), ("rad", 1)]
        case .area:
            [("mm²", 1e-6), ("cm²", 1e-4), ("m²", 1), ("ft²", 0.09290304)]
        case .volume:
            [("mL", 1e-6), ("L", 1e-3), ("m³", 1), ("ft³", 0.028316846592)]
        }
    }

    var units: [String] { table.map(\.0) }
    var factors: [String: Double] { Dictionary(uniqueKeysWithValues: table) }

    var defaults: (String, String) {
        switch self {
        case .length: ("m", "ft")
        case .angle: ("°", "rad")
        case .area: ("m²", "ft²")
        case .volume: ("L", "ft³")
        }
    }
}

private enum ConverterFormat {
    /// Significant figures of the input, clamped to 3...6. Values of 1000 or more are grouped with at most one decimal.
    static func format(_ n: Double, input: String) -> String {
        guard n.isFinite else { return "—" }
        if n == 0 { return "0" }
        var digits0 = input.filter(\.isNumber)
        while digits0.first == "0" { digits0.removeFirst() }
        let sig0 = min(6, max(3, digits0.count))
        // Outside 1e-6 ... 1e15 plain digits stop being readable: use scientific notation.
        if abs(n) < 1e-6 || abs(n) >= 1e15 {
            let parts = String(format: "%.\(sig0 - 1)e", n).split(separator: "e")
            guard parts.count == 2, let exp = Int(parts[1]) else { return "—" }
            var mantissa = String(parts[0])
            if mantissa.contains(".") {
                while mantissa.hasSuffix("0") { mantissa.removeLast() }
                if mantissa.hasSuffix(".") { mantissa.removeLast() }
            }
            return "\(mantissa)×10" + superscript(exp)
        }
        if abs(n) >= 1000 {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "en_AU")
            f.numberStyle = .decimal
            f.maximumFractionDigits = 1
            return f.string(from: NSNumber(value: n)) ?? "—"
        }
        var digits = input.filter(\.isNumber)
        while digits.first == "0" { digits.removeFirst() }
        let sig = min(6, max(3, digits.count))
        let rounded = Double(String(format: "%.\(sig - 1)e", n)) ?? n
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 12
        return f.string(from: NSNumber(value: rounded)) ?? "—"
    }

    private static func superscript(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
                                           "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).compactMap { map[$0] })
    }
}
