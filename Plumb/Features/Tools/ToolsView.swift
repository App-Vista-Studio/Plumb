//
//  ToolsView.swift
//  Plumb
//
//  Boards: 03 Tools library (Tools.dc.html) and 26 Tools grid sizes (Responsive.dc.html).
//  Standard iPhone uses the categorised library; compact, large and iPad use the Responsive layouts.
//

import SwiftUI

struct ToolsView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geo in
            let layout = ToolsLayout(width: geo.size.width, regular: sizeClass == .regular)
            ScrollView {
                switch layout {
                case .standard: ToolsLibrary()
                case .compact: ToolsFlatGrid(style: .compact)
                case .large: ToolsFlatGrid(style: .large)
                case .iPad: ToolsPadGrid()
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .background(PM.Colors.background.ignoresSafeArea())
    }
}

private enum ToolsLayout {
    case compact, standard, large, iPad

    init(width: CGFloat, regular: Bool) {
        if regular && width >= 600 { self = .iPad }
        else if width < 385 { self = .compact }
        else if width > 415 { self = .large }
        else { self = .standard }
    }
}

// MARK: - Catalogue

struct ToolsEntry: Identifiable {
    var id: String { name }
    let name: String
    let desc: String
    /// Icon path data exactly as drawn on the board.
    let icon: String
    let route: Route
    var pro = false
}

private enum ToolsIcons {
    static let level = "M6.5 8h11a4 4 0 0 1 0 8h-11a4 4 0 0 1 0-8z M10 12a2 2 0 1 0 4 0a2 2 0 1 0-4 0 M8 8v8M16 8v8"
    static let surface = "M3 15l8-6 10 3-8 6z M12 11V4 M10 6l2-2 2 2"
    static let calibrate = "M4 12a8 8 0 1 0 16 0a8 8 0 1 0-16 0 M12 2v4M12 18v4M2 12h4M18 12h4 M10.5 12a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0"
    static let ruler = "M4 7h16a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M6 7v4M10 7v3M14 7v4M18 7v3"
    static let photo = "M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z M7 15l10-6"
    static let ar = "M12 3l8 4.5v9L12 21l-8-4.5v-9z M12 12l8-4.5M12 12v9M12 12L4 7.5"
    static let room = "M4 4h16v16H4z M4 12h7v8M15 4v5"
    static let angle = "M4 20h16 M4 20L17 6 M11 20a7 7 0 0 0-2.1-5"
    static let protractor = "M3 17a9 9 0 0 1 18 0z M12 17l4-6 M7 17v-1M17 17v-1M12 9v1"
    static let slope = "M3 19h18L3 9z M7 19v-2"
    static let compass = "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0 M15.5 8.5l-2 5-5 2 2-5z"
    static let calc = "M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M8 7h8M8 11h2M14 11h2M8 15h2M14 15h2M8 18h2M14 18h2"
    static let convert = "M4 8h13l-3-3M20 16H7l3 3"
}

/// Icon set from the Responsive board (simplified level, surface and protractor glyphs).
private enum ToolsGridIcons {
    static let level = "M4.5 8h15a4 4 0 0 1 0 8h-15a4 4 0 0 1 0-8zM12 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"
    static let surface = "M3 15l9-5 9 5-9 5zM12 10V4"
    static let angle = "M4 20h16M4 20L17 6M11 20a7 7 0 0 0-2.1-5"
    static let protractor = "M3 17a9 9 0 0 1 18 0zM12 17l4-6"
    static let ruler = "M4 7h16a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM6 7v4M10 7v3M14 7v4M18 7v3"
    static let compass = "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM15.5 8.5l-2 5-5 2 2-5z"
    static let ar = "M12 3l8 4.5v9L12 21l-8-4.5v-9zM12 12l8-4.5M12 12v9M12 12L4 7.5"
    static let room = "M4 4h16v16H4zM4 12h7v8M15 4v5"
    static let photo = "M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zM7 15l10-6"
    static let slope = "M3 19h18L3 9zM7 19v-2"
    static let calc = "M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM8 7h8M8 11h2M14 11h2M8 15h2M14 15h2"
    static let convert = "M4 8h13l-3-3M20 16H7l3 3"
}

private struct ToolsCategory: Identifiable {
    var id: String { name }
    let name: String
    let sub: String
    let tools: [ToolsEntry]
}

private enum ToolsCatalogue {
    typealias I = ToolsIcons

    static let categories: [ToolsCategory] = [
        ToolsCategory(name: "LEVEL", sub: "Measure & Align", tools: [
            ToolsEntry(name: "Bubble Level", desc: "Find perfect balance", icon: I.level, route: .level),
            ToolsEntry(name: "Surface Level", desc: "Pitch and roll", icon: I.surface, route: .surface),
            ToolsEntry(name: "Calibration", desc: "Set your reference", icon: I.calibrate, route: .calibration),
        ]),
        ToolsCategory(name: "MEASURE", sub: "Distance & Size", tools: [
            ToolsEntry(name: "Ruler", desc: "On-screen length", icon: I.ruler, route: .ruler),
            ToolsEntry(name: "Photo Measure", desc: "Mark up a photo", icon: I.photo, route: .photo, pro: true),
        ]),
        ToolsCategory(name: "ANGLE", sub: "Angles & Slope", tools: [
            ToolsEntry(name: "Angle Finder", desc: "Inclination", icon: I.angle, route: .angle),
            ToolsEntry(name: "Protractor", desc: "0–180°", icon: I.protractor, route: .protractor),
            ToolsEntry(name: "Slope / Grade", desc: "Rise over run", icon: I.slope, route: .slope),
        ]),
        ToolsCategory(name: "DIRECTION", sub: "Compass & Orientation", tools: [
            ToolsEntry(name: "Compass", desc: "Magnetic or true north", icon: I.compass, route: .compass),
        ]),
        ToolsCategory(name: "AR", sub: "Spatial Measurement", tools: [
            ToolsEntry(name: "AR Measure", desc: "Point to point", icon: I.ar, route: .ar, pro: true),
            ToolsEntry(name: "Room Measure", desc: "Floor plan", icon: I.room, route: .room, pro: true),
        ]),
        ToolsCategory(name: "CALCULATORS", sub: "Construction Tools", tools: [
            ToolsEntry(name: "Construction", desc: "Area, volume and more", icon: I.calc, route: .calculators),
            ToolsEntry(name: "Unit Converter", desc: "Length, area, volume", icon: I.convert, route: .converter),
        ]),
    ]

    private typealias G = ToolsGridIcons

    static let levelGroup: [ToolsEntry] = [
        ToolsEntry(name: "Bubble Level", desc: "Find perfect balance", icon: G.level, route: .level),
        ToolsEntry(name: "Surface Level", desc: "Pitch and roll on a surface", icon: G.surface, route: .surface),
        ToolsEntry(name: "Angle Finder", desc: "Measure inclination", icon: G.angle, route: .angle),
        ToolsEntry(name: "Protractor", desc: "Measure any angle", icon: G.protractor, route: .protractor),
    ]
    static let measureGroup: [ToolsEntry] = [
        ToolsEntry(name: "Ruler", desc: "On-screen length", icon: G.ruler, route: .ruler),
        ToolsEntry(name: "Compass", desc: "Find direction", icon: G.compass, route: .compass),
        ToolsEntry(name: "AR Measure", desc: "Distance in space", icon: G.ar, route: .ar, pro: true),
        ToolsEntry(name: "Room Measure", desc: "Floor plan and area", icon: G.room, route: .room, pro: true),
    ]
    static let calcGroup: [ToolsEntry] = [
        ToolsEntry(name: "Photo Measure", desc: "Measure on a photo", icon: G.photo, route: .photo, pro: true),
        ToolsEntry(name: "Slope / Grade", desc: "Rise, run, percent", icon: G.slope, route: .slope),
        ToolsEntry(name: "Calculators", desc: "Area, volume and more", icon: G.calc, route: .calculators),
        ToolsEntry(name: "Unit Converter", desc: "Length, area, volume", icon: G.convert, route: .converter),
    ]
    static var all: [ToolsEntry] { levelGroup + measureGroup + calcGroup }
}

// MARK: - PRO gating

/// One rule for every PRO entry point (Home quick tools, recommendation, Tools library and grids):
/// without Pro, a PRO tool opens the paywall instead of the tool.
enum ProGate {
    static func route(_ route: Route, pro: Bool, settings: AppSettings = .shared) -> Route {
        pro && !settings.isPro ? .paywall : route
    }
}

// MARK: - Badge

/// PRO badge as drawn on the Tools boards: 20 tall, 7 pt padding, 12 heavy.
/// Free tools carry no badge, so only Pro tools stand out.
private struct ToolsBadge: View {
    var pro: Bool
    var tracking: CGFloat = 0.6

    var body: some View {
        if pro {
            Text("PRO")
                .font(.pm(12, .heavy))
                .tracking(tracking)
                .foregroundStyle(PM.Colors.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .overlay(Capsule().strokeBorder(PM.Colors.badgeOutline, lineWidth: 1))
        }
    }
}

/// Two-per-row equal-height grid rows, like CSS grid with `repeat(n, 1fr)`.
/// A lone card on the last row spans the full width instead of leaving a gap.
private struct ToolsGrid<Cell: View>: View {
    var items: [ToolsEntry]
    var columns: Int
    var spacing: CGFloat
    @ViewBuilder var cell: (ToolsEntry) -> Cell

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                GridRow {
                    if columns > 1 && start + 1 == items.count {
                        cell(items[start])
                            .gridCellColumns(columns)
                    } else {
                        ForEach(0..<columns, id: \.self) { i in
                            if start + i < items.count {
                                cell(items[start + i])
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Standard iPhone: categorised library

private struct ToolsLibrary: View {
    @Environment(Router.self) private var router
    @Environment(\.colorScheme) private var colorScheme
    /// LightMode board metrics for the utility theme.
    private var light: Bool { colorScheme == .light }
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [ToolsCategory] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ToolsCatalogue.categories }
        return ToolsCatalogue.categories.compactMap { c in
            let hit = c.name.lowercased().contains(q) || c.sub.lowercased().contains(q)
            let tools = hit ? c.tools : c.tools.filter {
                $0.name.lowercased().contains(q) || $0.desc.lowercased().contains(q)
            }
            return tools.isEmpty ? nil : ToolsCategory(name: c.name, sub: c.sub, tools: tools)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: light ? 12 : 16) {
            HStack {
                Text("Tools")
                    .pmTitleStyle()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconCircleButton(icon: .settings, label: "Settings") { router.push(.settings) }
            }

            searchField

            let cats = filtered
            if cats.isEmpty {
                Text("No tools match “\(query)”.")
                    .font(.pm(15))
                    .foregroundStyle(PM.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
            ForEach(cats) { c in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(c.name)
                            .font(.pm(light ? 13 : 12, light ? .heavy : .bold))
                            .tracking(1.2)
                            .foregroundStyle(PM.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(c.sub)
                            .font(.pm(13))
                            .foregroundStyle(PM.Colors.textSecondary)
                    }
                    ToolsGrid(items: c.tools, columns: 2, spacing: light ? 10 : 12) { t in
                        card(t)
                    }
                }
                .padding(.top, light ? 4 : 0)
            }

            Button { router.push(.paywall) } label: {
                HStack(spacing: 12) {
                    Text("Pro also adds Projects, PDF Reports, History and iCloud Sync.")
                        .font(.pm(13))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("See Pro")
                        .font(.pm(14, .bold))
                        .foregroundStyle(PM.Colors.accent)
                        .fixedSize()
                }
                .padding(16)
                .overlay(
                    RoundedRectangle(cornerRadius: PM.Radius.card, style: .continuous)
                        .strokeBorder(PM.Colors.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                )
                .contentShape(RoundedRectangle(cornerRadius: PM.Radius.card, style: .continuous))
            }
            .buttonStyle(.pmPress)
        }
        .padding(.top, (light ? 58 : 62) - PM.Board.statusBar)
        .padding(.horizontal, 20)
        .padding(.bottom, PMTabBar.visibleHeight + 22)
    }

    private func open(_ t: ToolsEntry) {
        searchFocused = false
        router.push(ProGate.route(t.route, pro: t.pro))
    }

    private var searchField: some View {
        HStack(spacing: light ? 10 : 12) {
            PMIcon(.search, size: 18, stroke: 2)
                .foregroundStyle(PM.Colors.textSecondary)
            TextField("", text: $query, prompt: Text("Search tools").foregroundStyle(PM.Colors.textSecondary))
                .font(.pm(15))
                .foregroundStyle(PM.Colors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .accessibilityLabel("Search tools")
            if !query.isEmpty {
                Button { query = "" } label: {
                    PMIcon(.close, size: 14, stroke: 2)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Capsule().fill(PM.Colors.surface))
        .overlay(Capsule().strokeBorder(PM.Colors.border, lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { searchFocused = true }
    }

    private func card(_ t: ToolsEntry) -> some View {
        Button { open(t) } label: {
            HStack(spacing: light ? 10 : 12) {
                SVGStroke(d: t.icon, size: light ? 20 : 22, lineWidth: 1.7)
                    .foregroundStyle(PM.Colors.accent)
                    .frame(width: light ? 34 : 38, height: light ? 34 : 38)
                    .background(RoundedRectangle(cornerRadius: light ? 11 : PM.Radius.iconWell, style: .continuous).fill(PM.Colors.iconWell))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name)
                        .font(.pm(14, .semibold))
                        .foregroundStyle(PM.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    // Reserve two lines so every card in a row has the same height.
                    Text(t.desc)
                        .font(.pm(12))
                        .lineSpacing(2)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EdgeInsets(top: light ? 28 : 32, leading: 12, bottom: 12, trailing: 12))
            .frame(maxWidth: .infinity, minHeight: light ? 84 : 94, maxHeight: .infinity, alignment: .leading)
            .pmCard(radius: light ? 20 : PM.Radius.card)
            .overlay(alignment: .topTrailing) {
                ToolsBadge(pro: t.pro, tracking: light ? 0.4 : 0.6).padding(.top, 8).padding(.trailing, light ? 10 : 8)
            }
        }
        .buttonStyle(.pmPress)
        .accessibilityLabel("\(t.name)\(t.pro ? ", Pro" : ""): \(t.desc)")
    }
}

// MARK: - Compact and large iPhone: flat grid

private struct ToolsFlatGrid: View {
    enum Style { case compact, large }
    var style: Style

    @Environment(Router.self) private var router

    private struct Metrics {
        let top, side, titleSize, columns, cardPadding, minHeight, well, wellRadius, iconSize, nameSize: CGFloat
    }

    private var m: Metrics {
        switch style {
        case .compact:
            Metrics(top: 56, side: 16, titleSize: 30, columns: 2, cardPadding: 14, minHeight: 112,
                    well: 36, wellRadius: 12, iconSize: 20, nameSize: 15)
        case .large:
            Metrics(top: 60, side: 18, titleSize: 32, columns: 3, cardPadding: 13, minHeight: 118,
                    well: 34, wellRadius: 11, iconSize: 19, nameSize: 14)
        }
    }

    var body: some View {
        let m = m
        VStack(alignment: .leading, spacing: 16) {
            Text("Tools")
                .font(.pm(m.titleSize, .bold))
                .tracking(-0.6)
                .foregroundStyle(PM.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ToolsGrid(items: ToolsCatalogue.all, columns: Int(m.columns), spacing: 10) { t in
                Button { router.push(ProGate.route(t.route, pro: t.pro)) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        SVGStroke(d: t.icon, size: m.iconSize, lineWidth: 1.7)
                            .foregroundStyle(PM.Colors.accent)
                            .frame(width: m.well, height: m.well)
                            .background(RoundedRectangle(cornerRadius: m.wellRadius, style: .continuous).fill(PM.Colors.iconWell))
                        Text(t.name)
                            .font(.pm(m.nameSize, .semibold))
                            .foregroundStyle(PM.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(t.desc)
                            .font(.pm(12))
                            .lineSpacing(1.3)
                            .foregroundStyle(PM.Colors.textSecondary)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(m.cardPadding)
                    .frame(maxWidth: .infinity, minHeight: m.minHeight, maxHeight: .infinity, alignment: .topLeading)
                    .pmCard()
                    .overlay(alignment: .topTrailing) {
                        ToolsBadge(pro: t.pro).padding(.top, 14).padding(.trailing, 12)
                    }
                }
                .buttonStyle(.pmPress)
                .accessibilityLabel("\(t.name)\(t.pro ? ", Pro" : ""): \(t.desc)")
            }
        }
        .padding(.top, m.top - PM.Board.statusBar)
        .padding(.horizontal, m.side)
        .padding(.bottom, PMTabBar.visibleHeight + 20)
    }
}

// MARK: - iPad: grouped four-column grid

private struct ToolsPadGrid: View {
    @Environment(Router.self) private var router

    private let groups: [(title: String, sub: String, items: [ToolsEntry])] = [
        ("LEVEL AND ANGLE", "Measure and align", ToolsCatalogue.levelGroup),
        ("MEASURE AND DIRECTION", "Distance, size and heading", ToolsCatalogue.measureGroup),
        ("PHOTO AND CALCULATORS", "Construction tools", ToolsCatalogue.calcGroup),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Tools")
                    .font(.pm(36, .bold))
                    .tracking(-0.8)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconCircleButton(icon: .settings, label: "Settings") { router.push(.settings) }
            }
            ForEach(groups, id: \.title) { g in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(g.title)
                            .font(.pm(13, .heavy))
                            .tracking(1.4)
                            .foregroundStyle(PM.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(g.sub)
                            .font(.pm(13))
                            .foregroundStyle(PM.Colors.textSecondary)
                    }
                    ToolsGrid(items: g.items, columns: 4, spacing: 14) { t in
                        Button { router.push(ProGate.route(t.route, pro: t.pro)) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                SVGStroke(d: t.icon, size: 24, lineWidth: 1.7)
                                    .foregroundStyle(PM.Colors.accent)
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PM.Colors.iconWell))
                                Text(t.name)
                                    .font(.pm(17, .semibold))
                                    .foregroundStyle(PM.Colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Text(t.desc)
                                    .font(.pm(13))
                                    .lineSpacing(13 * 0.15)
                                    .foregroundStyle(PM.Colors.textSecondary)
                            }
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(18)
                            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
                            .pmCard(radius: 26)
                            .overlay(alignment: .topTrailing) {
                                ToolsBadge(pro: t.pro).padding(.top, 14).padding(.trailing, 12)
                            }
                        }
                        .buttonStyle(.pmPress)
                        .accessibilityLabel("\(t.name)\(t.pro ? ", Pro" : ""): \(t.desc)")
                    }
                }
            }
        }
        .padding(.top, 48 - 24)
        .padding(.horizontal, 40)
        .padding(.bottom, PMTabBar.visibleHeight + 40)
    }
}

#Preview {
    RootView()
}
