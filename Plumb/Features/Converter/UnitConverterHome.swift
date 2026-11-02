//
//  UnitConverterHome.swift
//  Plumb
//
//  Unit Converter landing: search plus a 3-column grid of the 15 categories in UnitCatalog.
//  Tapping a tile pushes `.convert(category)`.
//

import SwiftUI

struct UnitConverterHome: View {
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var appeared = false
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3)

    /// Categories matching the search (title, subtitle, or any unit symbol or name), with the unit that matched.
    private var matches: [(category: UnitCategory, unit: UnitDef?)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return UnitCategory.allCases.map { ($0, nil) } }
        return UnitCategory.allCases.compactMap { c in
            let unit = c.units.first { $0.symbol.localizedCaseInsensitiveCompare(q) == .orderedSame }
                ?? c.units.first { $0.symbol.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) }
            if c.title.localizedCaseInsensitiveContains(q) || c.subtitle.localizedCaseInsensitiveContains(q) { return (c, nil) }
            return unit.map { (c, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ConverterTopBar(title: "Unit Converter", backLabel: "Back to tools") { router.pop() } trailing: {
                TopBarPlaceholder()
            }
            .padding(.horizontal, 20)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    searchField
                    let items = matches
                    if items.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.element.category) { i, item in
                                tile(item.category, matched: item.unit, index: i)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(.top, 56 + 1 - PM.Board.statusBar)
        .background(PM.Colors.background.ignoresSafeArea())
        .onAppear { appeared = true }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 10) {
            PMIcon(.search, size: 18, stroke: 2)
                .foregroundStyle(PM.Colors.textTertiary)
            TextField("", text: $query, prompt: Text("Search units, e.g. psi or acre").foregroundStyle(PM.Colors.textTertiary))
                .font(.pm(16))
                .foregroundStyle(PM.Colors.textPrimary)
                .tint(PM.Colors.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit {
                    if let only = matches.first, matches.count == 1 { open(only.category) }
                }
                .accessibilityLabel("Search units")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    PMIcon(.close, size: 14, stroke: 2.2)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -12)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .pmCard(radius: PM.Radius.cardSmall)
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No units match “\(query)”")
                .font(.pm(15, .semibold))
                .foregroundStyle(PM.Colors.textPrimary)
            Text("Try a symbol like kPa, or a name like gallon.")
                .font(.pm(13))
                .foregroundStyle(PM.Colors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: Tile

    private func tile(_ c: UnitCategory, matched: UnitDef?, index: Int) -> some View {
        let detail = matched.map { "\($0.symbol) · \($0.name)" } ?? c.subtitle
        return Button { open(c) } label: {
            VStack(alignment: .center, spacing: 10) {
                PMIcon(c.icon, size: 22)
                    .foregroundStyle(PM.Colors.accent)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: PM.Radius.iconWell, style: .continuous).fill(PM.Colors.iconWell))
                VStack(alignment: .center, spacing: 3) {
                    Text(c.title)
                        .font(.pm(13, .bold))
                        .foregroundStyle(PM.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(detail)
                        .font(.pm(11))
                        .foregroundStyle(matched == nil ? PM.Colors.textSecondary : PM.Colors.accent)
                        .lineLimit(2, reservesSpace: true)
                        .minimumScaleFactor(0.85)
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .top)
            .pmCard(radius: PM.Radius.cardSmall)
        }
        .buttonStyle(.pmPress)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 14)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
        .animation(reduceMotion
                   ? .easeOut(duration: 0.2)
                   : .spring(response: 0.45, dampingFraction: 0.86).delay(Double(index) * 0.03),
                   value: appeared)
        .accessibilityLabel("\(c.title): \(detail)")
        .accessibilityHint("\(c.units.count) units")
    }

    private func open(_ c: UnitCategory) {
        searchFocused = false
        Haptics.selection()
        router.push(.convert(c))
    }
}

extension UnitCategory {
    /// Category glyph for tiles and headers.
    var icon: PMIconName {
        switch self {
        case .length: .ruler
        case .area: .unitArea
        case .volume: .unitVolume
        case .weight: .unitWeight
        case .pressure: .unitPressure
        case .angle: .angle
        case .power: .unitPower
        case .force: .unitForce
        case .work: .unitEnergy
        case .temperature: .unitTemperature
        case .speed: .unitSpeed
        case .time: .unitTime
        case .fuel: .unitFuel
        case .voltage: .unitVoltage
        case .data: .unitData
        }
    }
}

/// Converter header: back button, centred title, one trailing slot. Matches the board's 46 pt bar.
struct ConverterTopBar<Trailing: View>: View {
    var title: String
    var backLabel: String = "Back"
    var onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(.pm(17, .bold))
                .foregroundStyle(PM.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 52)
                .accessibilityAddTraits(.isHeader)
            HStack {
                IconCircleButton(icon: .back, label: backLabel, stroke: 2, action: onBack)
                Spacer()
                trailing()
            }
        }
        .frame(height: 46) // 44 link + 1 px border outside the box on the board
    }
}
