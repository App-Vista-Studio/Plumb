//
//  UnitConvertView.swift
//  Plumb
//
//  One category of the Unit Converter: FROM/TO panels with unit chips, swap, a collapsible custom
//  keypad (opened by tapping the FROM value), and an "All units" list converting the value into
//  every unit of the category. All numbers come from
//  UnitCatalog (`UnitCategory.convert`); formatting from ConverterFormat.
//

import SwiftUI
import UIKit

struct UnitConvertView: View {
    let category: UnitCategory
    private let units: [UnitDef]

    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    // The last conversion of each category is kept between visits.
    @AppStorage private var storedValue: String
    @AppStorage private var storedFrom: String
    @AppStorage private var storedTo: String
    @AppStorage("converter.allUnitsExpanded") private var expanded = true
    @State private var toast: String?
    /// The keypad starts collapsed so the panels and the All units list get the screen;
    /// tapping the FROM value opens it. UI state only, never stored.
    @State private var keypadOpen = DebugLaunch.is("keypad")

    init(category: UnitCategory) {
        self.category = category
        self.units = category.units
        let key = "converter.\(category.rawValue)."
        _storedValue = AppStorage(wrappedValue: "1", key + "value")
        _storedFrom = AppStorage(wrappedValue: category.defaultPair.from, key + "from")
        _storedTo = AppStorage(wrappedValue: category.defaultPair.to, key + "to")
    }

    // MARK: Derived values

    /// Sanitised keypad string: digits, one decimal point, a leading minus only for temperature.
    private var value: String { ConverterInput.sanitise(storedValue, allowsNegative: category.allowsNegative) }
    private var number: Double? { ConverterInput.number(value) }
    private var fromUnit: UnitDef { unit(storedFrom) ?? unit(category.defaultPair.from) ?? units[0] }
    private var toUnit: UnitDef { unit(storedTo) ?? unit(category.defaultPair.to) ?? units[min(1, units.count - 1)] }

    private func unit(_ id: String) -> UnitDef? { units.first { $0.id == id } }

    private func converted(to u: UnitDef) -> Double? {
        guard let n = number else { return nil }
        return UnitCategory.convert(n, from: fromUnit, to: u)
    }

    /// Formatted value in `u`; the FROM unit shows the typed value itself.
    private func display(_ u: UnitDef) -> String {
        if u.id == fromUnit.id { return number.map(ConverterFormat.format) ?? ConverterFormat.placeholder }
        return converted(to: u).map(ConverterFormat.format) ?? ConverterFormat.placeholder
    }

    private var result: String {
        // FROM and TO can only match through stale storage; show the conversion anyway.
        converted(to: toUnit).map(ConverterFormat.format) ?? ConverterFormat.placeholder
    }

    private var hasResult: Bool { result != ConverterFormat.placeholder }
    private var shareText: String { "\(ConverterFormat.input(value)) \(fromUnit.symbol) = \(result) \(toUnit.symbol)" }

    private var valueAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.25) }
    private var pickAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.82) }

    // MARK: Body

    var body: some View {
        GeometryReader { g in
            // Measured like the board: full height below the status bar, home indicator included.
            let bottomInset = g.safeAreaInsets.bottom
            let fit = ConverterLayout.fit(forHeight: g.size.height + bottomInset)
            VStack(spacing: ConverterLayout.lerp(8, 12, fit)) {
                ConverterTopBar(title: category.title, backLabel: "Back to unit categories") { router.pop() } trailing: {
                    shareButton
                }
                .padding(.horizontal, 20)

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: ConverterLayout.lerp(8, 12, fit)) {
                            panels(fit: fit)
                            allUnits
                                .padding(.top, ConverterLayout.lerp(4, 8, fit))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        // Collapsed, the list runs to the screen bottom: keep its last row above the
                        // home indicator. Open, the keypad's safe-area inset already lifts it.
                        .padding(.bottom, keypadOpen ? 14 : bottomInset + 14)
                        .id(Self.topID)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    // Scrolling the list means the user is reading, not typing: put the keypad away.
                    .onScrollPhaseChange { _, phase in
                        if phase == .interacting, keypadOpen { setKeypad(false) }
                    }
                    // Content scrolling under the top bar or the home indicator fades instead of being cut.
                    .mask(
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 6)
                            Rectangle().fill(.black)
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
                        }
                    )
                    // The keypad is a bottom inset, so the scroll content is inset by its height.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if keypadOpen {
                            keypadPanel(fit: fit, bottomInset: bottomInset)
                                .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                        }
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                    .onChange(of: keypadOpen) { _, open in
                        // Opening: bring both panels into view so FROM and TO stay visible while typing.
                        if open { withAnimation(keypadAnimation) { proxy.scrollTo(Self.topID, anchor: .top) } }
                    }
                }
            }
            .padding(.top, 56 + 1 - PM.Board.statusBar)
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let toast {
                ToastView(text: toast)
                    .padding(.top, 60)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
    }

    private static let topID = "converter.top"

    private var keypadAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private func setKeypad(_ open: Bool) {
        guard open != keypadOpen else { return }
        withAnimation(keypadAnimation) { keypadOpen = open }
        if open { Haptics.selection() }
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    // MARK: Keypad panel

    private func keypadPanel(fit: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Capsule()
                    .fill(PM.Colors.borderStrong)
                    .frame(width: 36, height: 5)
                    .accessibilityHidden(true)
                HStack {
                    Spacer()
                    Button { setKeypad(false) } label: {
                        HStack(spacing: 6) {
                            Text("Done").font(.pm(15, .semibold))
                            PMIcon(.back, size: 14, stroke: 2.2).rotationEffect(.degrees(-90))
                        }
                        .foregroundStyle(PM.Colors.accent)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pmPress)
                    .padding(.trailing, -12)
                    .accessibilityLabel("Hide keypad")
                }
            }
            .frame(height: 36)
            .contentShape(Rectangle())
            // A downward swipe on the header also puts the keypad away.
            .gesture(DragGesture(minimumDistance: 12).onEnded { v in
                if v.translation.height > 30 { setKeypad(false) }
            })

            ConverterKeypad(keyHeight: ConverterLayout.lerp(44, 54, fit), gap: ConverterLayout.lerp(6, 8, fit), press: press)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, max(12, bottomInset - 8))
        .background(
            UnevenRoundedRectangle(topLeadingRadius: PM.Radius.card, topTrailingRadius: PM.Radius.card, style: .continuous)
                .fill(PM.Colors.segmentTrack)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: PM.Radius.card, topTrailingRadius: PM.Radius.card, style: .continuous)
                        .stroke(PM.Colors.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 16, y: -4)
                .ignoresSafeArea(.container, edges: .bottom)
        )
    }

    // MARK: Top bar

    private var shareButton: some View {
        ShareLink(item: shareText) {
            PMIcon(.share, size: 20, stroke: 1.8)
                .foregroundStyle(hasResult ? PM.Colors.textPrimary : PM.Colors.textTertiary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(PM.Colors.surface))
                .overlay(Circle().strokeBorder(PM.Colors.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pmPress)
        .disabled(!hasResult)
        .accessibilityLabel("Share conversion")
    }

    // MARK: Panels

    @ViewBuilder
    private func panels(fit: CGFloat) -> some View {
        ConverterPanel(title: "FROM", tag: "User-entered", tagColor: PM.Colors.calibrating,
                       fill: PM.Colors.surface, value: ConverterFormat.input(value), valueColor: PM.Colors.textPrimary,
                       spokenValue: ConverterSpeech.value(ConverterFormat.input(value)),
                       unit: fromUnit, units: units, prefix: "From", spokenNumber: number, fit: fit,
                       valueAccessory: category.allowsNegative ? AnyView(signButton) : nil,
                       editing: keypadOpen, onEdit: { setKeypad(true) }) { id in
            withAnimation(pickAnimation) { pickFrom(id) }
        }

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
                       spokenValue: ConverterSpeech.value(result),
                       unit: toUnit, units: units, prefix: "To", spokenNumber: converted(to: toUnit), fit: fit,
                       headerAccessory: AnyView(copyButton)) { id in
            withAnimation(pickAnimation) { storedTo = id }
        }
        .contextMenu {
            Button("Copy \(result) \(toUnit.symbol)", systemImage: "doc.on.doc") { copy(result, toUnit) }
                .disabled(!hasResult)
        }
        .accessibilityAction(named: "Copy result") { copy(result, toUnit) }
    }

    private var copyButton: some View {
        Button { copy(result, toUnit) } label: {
            PMIcon(.copy, size: 16, stroke: 1.8)
                .foregroundStyle(hasResult ? PM.Colors.textSecondary : PM.Colors.textTertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pmPress)
        .disabled(!hasResult)
        .padding(.vertical, -14)
        .padding(.trailing, -12)
        .accessibilityLabel("Copy result")
    }

    /// ± for temperatures (the only category that allows negative values).
    private var signButton: some View {
        Button { press("±") } label: {
            Text("+/−")
                .font(.pm(15, .bold))
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(minWidth: 52, minHeight: 44)
                .background(Capsule().fill(PM.Colors.surfaceRaised))
                .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pmPress)
        .accessibilityLabel(value.hasPrefix("-") ? "Make positive" : "Make negative")
    }

    // MARK: All units

    private var allUnits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("ALL UNITS").pmCaptionStyle()
                    Text("\(units.count)")
                        .font(.pm(12, .bold))
                        .monospacedDigit()
                        .foregroundStyle(PM.Colors.textTertiary)
                    Spacer()
                    PMIcon(.chevronRight, size: 16, stroke: 2)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All units, \(units.count)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the list" : "Shows the value in every unit")
            .padding(.vertical, -6)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(units.enumerated()), id: \.element.id) { i, u in
                        resultRow(u, first: i == 0)
                    }
                }
                .padding(4)
                .pmCard(radius: PM.Radius.cardSmall)
                .transition(.opacity.combined(with: .move(edge: .top)))

                Text(footnote)
                    .font(.pm(12))
                    .foregroundStyle(PM.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    private var footnote: String {
        let note = category.sourceNote
        return units.contains { !$0.exact } ? note + " ≈ marks a rounded factor." : note
    }

    private func resultRow(_ u: UnitDef, first: Bool) -> some View {
        let isFrom = u.id == fromUnit.id
        let isTo = u.id == toUnit.id && !isFrom
        let shown = display(u)
        let n: Double? = isFrom ? number : converted(to: u)
        return Button {
            if isFrom {
                swap()
            } else {
                withAnimation(pickAnimation) { storedTo = u.id }
                Haptics.selection()
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(u.symbol)
                            .font(.pm(15, .semibold))
                            .foregroundStyle(PM.Colors.textPrimary)
                            .lineLimit(1)
                        if !u.exact {
                            Text("≈").font(.pm(13, .bold)).foregroundStyle(PM.Colors.warning)
                        }
                        if isFrom { rowTag("FROM", PM.Colors.calibrating) }
                        if isTo { rowTag("TO", PM.Colors.accent) }
                    }
                    Text(u.name)
                        .font(.pm(12))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Text(shown)
                    .font(.pm(17, isTo ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isTo ? PM.Colors.accent : PM.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .layoutPriority(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if isTo {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PM.Colors.accent.opacity(0.12))
                        .matchedGeometryEffect(id: "to", in: highlight)
                }
            }
            .overlay(alignment: .top) {
                if !first {
                    Rectangle().fill(PM.Colors.divider).frame(height: 1).padding(.horizontal, 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pmPress)
        .contextMenu {
            Button("Copy \(shown) \(u.symbol)", systemImage: "doc.on.doc") { copy(shown, u) }
                .disabled(shown == ConverterFormat.placeholder)
            if !isFrom {
                Button("Convert from \(u.symbol)", systemImage: "arrow.up.circle") { useAsFrom(u) }
                    .disabled(n == nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ConverterSpeech.value(shown)) \(ConverterSpeech.unit(name: u.name, for: n))")
        .accessibilityValue(isFrom ? "From unit" : isTo ? "To unit" : "")
        .accessibilityHint(isFrom ? "Double-tap to swap units" : "Double-tap to convert to this unit")
        .accessibilityAddTraits(isTo ? .isSelected : [])
        .accessibilityAction(named: "Copy value") { copy(shown, u) }
        .accessibilityAction(named: "Convert from this unit") { useAsFrom(u) }
    }

    private func rowTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.pm(9, .heavy))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
    }

    // MARK: Actions

    private func press(_ key: String) {
        let next = ConverterInput.press(key, on: value, allowsNegative: category.allowsNegative)
        guard next != value else { return }
        withAnimation(valueAnimation) { storedValue = next }
    }

    private func pickFrom(_ id: String) {
        // Picking the TO unit as FROM swaps them, so the pair never collapses to one unit.
        if id == toUnit.id { storedTo = fromUnit.id }
        storedFrom = id
    }

    private func swap() {
        // A result the keypad can't express (scientific, or longer than 10 digits) keeps the input.
        let typed = converted(to: toUnit).flatMap { ConverterFormat.typable($0, allowsNegative: category.allowsNegative) }
        let (f, t) = (fromUnit.id, toUnit.id)
        withAnimation(pickAnimation) {
            storedFrom = t
            storedTo = f
            if let typed { storedValue = typed }
        }
        Haptics.selection()
    }

    /// Makes `u` the FROM unit while keeping the same quantity (its converted value becomes the input).
    private func useAsFrom(_ u: UnitDef) {
        guard let x = converted(to: u) else { return }
        let typed = ConverterFormat.typable(x, allowsNegative: category.allowsNegative)
        let oldFrom = fromUnit.id
        withAnimation(pickAnimation) {
            if u.id == toUnit.id { storedTo = oldFrom }
            storedFrom = u.id
            storedValue = typed ?? value
        }
        if typed == nil { showToast("Value too long to type; kept input") }
        Haptics.selection()
    }

    private func copy(_ shown: String, _ u: UnitDef) {
        guard shown != ConverterFormat.placeholder else { return }
        UIPasteboard.general.string = "\(shown) \(u.symbol)"
        Haptics.selection()
        showToast("Copied")
        UIAccessibility.post(notification: .announcement, argument: "Copied \(ConverterSpeech.value(shown)) \(ConverterSpeech.unit(name: u.name))")
    }

    private func showToast(_ text: String) {
        withAnimation(PM.Motion.normal) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(PM.Motion.normal) { toast = nil }
        }
    }
}

// MARK: - Layout

enum ConverterLayout {
    /// 0 on the shortest supported phone (iPhone SE, 647 pt below the status bar), 1 from the
    /// 844 pt board size up (797 pt there; 780 so every 844 pt+ phone gets the board layout).
    static func fit(forHeight h: CGFloat) -> CGFloat {
        min(1, max(0, (h - 647) / (780 - 647)))
    }

    /// Compact value at `fit` 0, board value at `fit` 1, rounded to whole points.
    static func lerp(_ compact: CGFloat, _ board: CGFloat, _ fit: CGFloat) -> CGFloat {
        (compact + (board - compact) * fit).rounded()
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
    var spokenValue: String
    var unit: UnitDef
    var units: [UnitDef]
    var prefix: String
    var spokenNumber: Double?
    /// 0 on the shortest phone, 1 at the board size (see `ConverterLayout.fit`).
    var fit: CGFloat = 1
    var headerAccessory: AnyView? = nil
    var valueAccessory: AnyView? = nil
    /// Non-nil makes the value an editable field: tapping it calls `onEdit` (opens the keypad).
    var editing: Bool? = nil
    var onEdit: (() -> Void)? = nil
    var onPick: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var caretOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: ConverterLayout.lerp(6, 8, fit)) {
            HStack(spacing: 8) {
                Text(title).pmCaptionStyle()
                Spacer()
                Text(tag).font(.pm(12, .semibold)).foregroundStyle(tagColor)
                if let headerAccessory { headerAccessory }
            }
            HStack(alignment: .center, spacing: 10) {
                if let editing, let onEdit {
                    Button(action: onEdit) {
                        HStack(alignment: .center, spacing: 8) {
                            readout(caret: editing)
                            if !editing {
                                PMIcon(.pencil, size: 16, stroke: 1.8)
                                    .foregroundStyle(PM.Colors.textTertiary)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PM.Colors.background))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(editing ? PM.Colors.accent : PM.Colors.border, lineWidth: editing ? 1.5 : 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, -4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(editing
                                        ? "Value, \(spokenValue) \(ConverterSpeech.unit(name: unit.name, for: spokenNumber))"
                                        : "Edit value, \(spokenValue) \(ConverterSpeech.unit(name: unit.name, for: spokenNumber))")
                    .accessibilityHint(editing ? "Type with the keypad below" : "Opens the keypad")
                    .accessibilityAddTraits([.isButton, .updatesFrequently])
                } else {
                    readout(caret: false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(title.capitalized), \(spokenValue) \(ConverterSpeech.unit(name: unit.name, for: spokenNumber))")
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if let valueAccessory { valueAccessory }
            }

            // The selected chip is scrolled to the centre so it never sits under the edge fade.
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(units) { u in
                            chip(u)
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
                .onAppear { proxy.scrollTo(unit.id, anchor: .center) }
                .onChange(of: unit.id) { _, id in
                    withAnimation(PM.Motion.normal) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .padding(.horizontal, -16)
        }
        .padding(.vertical, ConverterLayout.lerp(10, 15, fit))
        .padding(.horizontal, 17)
        .pmCard(fill: fill)
    }

    /// Value and unit symbol; the board renders the 22 px unit with no gap after the value.
    /// While editing, a blinking caret sits between them (steady with Reduce Motion).
    private func readout(caret: Bool) -> some View {
        let valueSize = ConverterLayout.lerp(36, 44, fit)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(value)
                .font(.pm(valueSize, .light))
                .foregroundStyle(valueColor)
                .tracking(-1)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
                .layoutPriority(1)
            if caret {
                RoundedRectangle(cornerRadius: 1)
                    .fill(PM.Colors.accent)
                    .frame(width: 2, height: (valueSize * 0.78).rounded())
                    .padding(.horizontal, 2)
                    .opacity(caretOn ? 1 : 0)
                    .onAppear {
                        caretOn = true
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { caretOn = false }
                    }
                    .onDisappear { caretOn = true }
            }
            Text(unit.symbol)
                .font(.pm(ConverterLayout.lerp(18, 22, fit)))
                .foregroundStyle(PM.Colors.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ u: UnitDef) -> some View {
        let on = u.id == unit.id
        return Button { onPick(u.id) } label: {
            Text(u.symbol)
                .font(.pm(14, .bold))
                .foregroundStyle(on ? PM.Colors.onThumb : PM.Colors.textSecondary)
                .lineLimit(1)
                .fixedSize()
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
        .id(u.id)
        .accessibilityLabel("\(prefix) \(ConverterSpeech.unit(name: u.name))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Keypad

private struct ConverterKeypad: View {
    /// 54 on the board; never below 44 so every key stays a full touch target.
    var keyHeight: CGFloat = 54
    var gap: CGFloat = 8
    var press: (String) -> Void
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 3), spacing: gap) {
            ForEach(keys, id: \.self) { k in
                Button { press(k) } label: {
                    Text(k)
                        .font(.pm(24))
                        .monospacedDigit()
                        .foregroundStyle(PM.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(44, keyHeight))
                        .pmCard(radius: 18, fill: PM.Colors.surfaceRaised)
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
