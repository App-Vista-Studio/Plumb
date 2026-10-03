//
//  HomeView.swift
//  Plumb
//
//  Board: 01 Home (Main.dc.html).
//

import SwiftUI

struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(MeasurementStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var motion = MotionService.shared
    @State private var zoom = HomeZoomCoordinator.shared
    @State private var dialFrame: CGRect = .zero
    @State private var zoomDirection: HomeZoomDirection?

    private var reading: HomeLevelReading {
        // Simulator preview (Debug, no sensor) shows the board's 0.4° NEARLY LEVEL.
        let preview = motion.isPreview
        return HomeLevelReading(pitch: preview ? 0.26 : motion.pitch, roll: preview ? -0.3 : motion.roll,
                         perfectTolerance: settings.perfectTolerance,
                         nearlyTolerance: settings.nearlyTolerance)
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            if colorScheme == .light {
                // LightMode board: the utility theme uses a compact Quick Measure card.
                VStack(alignment: .leading, spacing: 14) {
                    header
                    lightQuickMeasure
                    lightButtons
                    Text("Quick Tools")
                        .font(.pm(19, .bold))
                        .foregroundStyle(PM.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 4)
                    lightQuickTools
                    lightRecent
                    projects.padding(.top, 10)
                    recommended
                    freePlan
                }
                .padding(.top, 58 - PM.Board.statusBar)
                .padding(.horizontal, 20)
                .padding(.bottom, PMTabBar.visibleHeight + 40)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    quickMeasure
                    quickTools
                    recent
                    projects
                    recommended
                    freePlan
                }
                .padding(.top, 62 - PM.Board.statusBar)
                .padding(.horizontal, 20)
                .padding(.bottom, PMTabBar.visibleHeight + 74)
            }
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(Self.debugScrollAnchor)
        .background {
            if colorScheme == .light { PM.Colors.background.ignoresSafeArea() } else { GridBackdrop() }
        }
        .onAppear {
            motion.start()
            if zoom.pendingReturn {
                zoom.pendingReturn = false
                DispatchQueue.main.async {
                    homeWithoutAnimation { zoomDirection = .close }
                }
            }
        }
        .onDisappear { motion.stop() }
        .fullScreenCover(isPresented: Binding(get: { zoomDirection != nil },
                                              set: { if !$0 { zoomDirection = nil } })) {
            if let dir = zoomDirection {
                HomeZoomOverlay(direction: dir, origin: dialFrame, bubbleOffset: reading.bubbleOffset) {
                    homeWithoutAnimation {
                        if dir == .open { router.push(.liveMeasure) }
                        zoomDirection = nil
                    }
                }
                .presentationBackground(.clear)
            }
        }
    }

    /// Design review only: `-state bottom` / `-state middle` open the scroll view part way down.
    private static var debugScrollAnchor: UnitPoint? {
        switch DebugLaunch.state {
        case "bottom": .bottom
        case "middle": .center
        default: nil
        }
    }

    // MARK: Header

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            let light = colorScheme == .light
            VStack(alignment: .leading, spacing: light ? 3 : 4) {
                Text(greeting)
                    .font(.pm(13, .semibold))
                    .foregroundStyle(PM.Colors.textSecondary)
                Text("Plumb")
                    .font(.pm(light ? 28 : 30, .bold)).tracking(-0.6)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Precision tools in your pocket.")
                    .font(.pm(light ? 14 : 15))
                    .foregroundStyle(PM.Colors.textSecondary)
            }
            Spacer(minLength: 8)
            IconCircleButton(icon: .settings, label: "Settings") { router.push(.settings) }
        }
    }

    // MARK: Quick Measure

    private var quickMeasure: some View {
        VStack(spacing: 24) {
            HStack {
                Text("QUICK MEASURE").pmCaptionStyle()
                Spacer(minLength: 8)
                LivePill(text: "Live · Device motion")
            }

            Button(action: openLive) {
                HomeLevelDial(bubbleOffset: reading.bubbleOffset,
                              showPulse: true,
                              showParticles: true,
                              drift: !motion.isAvailable)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(zoomDirection == nil ? 1 : 0)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { dialFrame = $0 }
            .accessibilityLabel("Open Live Measurement Mode")

            VStack(spacing: 4) {
                Text(reading.magnitudeText)
                    .font(.pm(44, .light))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(PM.Colors.textPrimary)
                statusLine
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                Button { router.push(.level) } label: {
                    HStack(spacing: 8) {
                        PMIcon(.levelPlain, size: 20, stroke: 1.7)
                        Text("Start Measuring")
                    }
                }
                .buttonStyle(.pmPrimary)

                Button("All Tools") { router.select(.tools) }
                    .buttonStyle(PMSecondaryButtonStyle(fontSize: 17))
            }
        }
        .padding(20)
        .pmCard(radius: PM.Radius.hero, fill: PM.Colors.surfaceSunken)
    }

    @ViewBuilder private var statusLine: some View {
        let r = reading
        HStack(spacing: 6) {
            switch r.status {
            case .perfect:
                PMIcon(.check, size: 14, stroke: 2.6)
                Text("PERFECTLY LEVEL")
            case .nearly:
                PMIcon(.nearly, size: 14, stroke: 2)
                Text("NEARLY LEVEL")
            case .off:
                PMIcon(.arrowUp, size: 14, stroke: 2).rotationEffect(.degrees(r.arrowRotation))
                Text(r.directionText)
            }
        }
        .font(.pm(13, .bold))
        .tracking(1.2)
        .foregroundStyle(r.status == .perfect ? PM.Colors.accent : PM.Colors.textSecondary)
    }

    private func openLive() {
        zoom.originFrame = dialFrame
        homeWithoutAnimation { zoomDirection = .open }
    }

    // MARK: Light variant (LightMode board)

    private var lightQuickMeasure: some View {
        Button { router.push(.level) } label: {
            HStack(spacing: 16) {
                HomeMiniDial(bubbleOffset: reading.bubbleOffset)
                VStack(alignment: .leading, spacing: 6) {
                    Text("QUICK MEASURE · LIVE").pmCaptionStyle()
                    Text(reading.magnitudeText)
                        .font(.pm(36, .light)).tracking(-1)
                        .monospacedDigit()
                        .foregroundStyle(PM.Colors.textPrimary)
                    lightStatus
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(PM.Colors.surface)
                .shadow(color: Color(hex: 0x0E1113, opacity: 0.05), radius: 12, y: 8))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(PM.Colors.border, lineWidth: 1))
        }
        .buttonStyle(.pmPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quick Measure, \(reading.magnitudeText), \(lightStatusText.lowercased())")
        .accessibilityHint("Opens the Bubble Level")
    }

    private var lightStatusText: String {
        switch reading.status {
        case .perfect: "PERFECTLY LEVEL"
        case .nearly: "NEARLY LEVEL"
        case .off: reading.directionText
        }
    }

    private var lightStatus: some View {
        let r = reading
        return HStack(spacing: 5) {
            switch r.status {
            case .perfect: PMIcon(.check, size: 13, stroke: 2.6)
            case .nearly: PMIcon(.nearly, size: 13, stroke: 2.2)
            case .off: PMIcon(.arrowUp, size: 13, stroke: 2.2).rotationEffect(.degrees(r.arrowRotation))
            }
            Text(lightStatusText)
        }
        .font(.pm(12, .bold))
        .tracking(1)
        .foregroundStyle(r.status == .perfect ? PM.Colors.accent : PM.Colors.textSecondary)
    }

    private var lightButtons: some View {
        HStack(spacing: 10) {
            Button("Start Measuring") { router.push(.level) }
                .buttonStyle(PMPrimaryButtonStyle(height: 52, fontSize: 16))
            Button("All Tools") { router.select(.tools) }
                .buttonStyle(PMSecondaryButtonStyle(height: 52, fontSize: 15))
        }
    }

    private var lightTools: [QuickTool] {
        tools.map { t in
            var t = t
            if t.id == "AR MEASURE" { t = QuickTool(id: "AR", desc: t.desc, icon: t.icon, route: t.route, pro: true) }
            if t.id == "PROTRACTOR" { t = QuickTool(id: t.id, desc: "Any angle", icon: t.icon, route: t.route) }
            return t
        }
    }

    private var lightQuickTools: some View {
        let list = lightTools
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(list[(row * 3)..<(row * 3 + 3)]) { t in
                        Button { router.push(ProGate.route(t.route, pro: t.pro)) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                PMIcon(t.icon, size: 20)
                                    .foregroundStyle(PM.Colors.accent)
                                    .frame(width: 34, height: 34)
                                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(PM.Colors.iconWell))
                                Text(t.id)
                                    .font(.pm(12, .heavy)).tracking(0.4)
                                    .foregroundStyle(PM.Colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                BoardWrapText(t.desc, size: 12, lineHeight: 1.3, color: PM.Colors.textSecondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
                            .pmCard(radius: 20)
                        }
                        .buttonStyle(.pmPress)
                        .accessibilityLabel("\(t.id.capitalized): \(t.desc)\(t.pro ? ", Pro" : "")")
                    }
                }
            }
        }
    }

    @ViewBuilder private var lightRecent: some View {
        if let m = recentRecord {
            Button { router.select(.history) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name)
                            .font(.pm(14, .semibold))
                            .foregroundStyle(PM.Colors.textPrimary)
                        Text(Self.metaLine([m.source.rawValue, Self.timeFormatter.string(from: m.date)]))
                            .font(.pm(12))
                            .foregroundStyle(PM.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(m.value)
                        .font(.pm(20, .medium))
                        .monospacedDigit()
                        .foregroundStyle(PM.Colors.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .pmCard(radius: 20)
            }
            .buttonStyle(.pmPress)
            .accessibilityLabel("Recent measurement: \(m.name), \(m.value)")
            .accessibilityHint("Opens History")
        }
    }

    // MARK: Quick Tools

    private struct QuickTool: Identifiable {
        let id: String
        let desc: String
        let icon: PMIconName
        let route: Route
        var pro = false
    }

    private let tools: [QuickTool] = [
        QuickTool(id: "LEVEL", desc: "Find perfect balance", icon: .level, route: .level),
        QuickTool(id: "ANGLE", desc: "Measure inclination", icon: .angle, route: .angle),
        QuickTool(id: "RULER", desc: "Measure length", icon: .ruler, route: .ruler),
        QuickTool(id: "COMPASS", desc: "Find direction", icon: .compass, route: .compass),
        QuickTool(id: "AR MEASURE", desc: "Measure in space", icon: .ar, route: .ar, pro: true),
        QuickTool(id: "PROTRACTOR", desc: "Measure any angle", icon: .protractor, route: .protractor),
    ]

    private var quickTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Quick Tools") { router.select(.tools) }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(tools[(row * 3)..<(row * 3 + 3)]) { tool in
                            quickToolTile(tool)
                        }
                    }
                }
            }
        }
    }

    private func quickToolTile(_ t: QuickTool) -> some View {
        Button { router.push(ProGate.route(t.route, pro: t.pro)) } label: {
            VStack(alignment: .leading, spacing: 12) {
                PMIcon(t.icon, size: 22)
                    .foregroundStyle(PM.Colors.accent)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: PM.Radius.iconWell, style: .continuous).fill(PM.Colors.iconWell))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.id)
                        .font(.pm(12, .bold))
                        .foregroundStyle(PM.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    BoardWrapText(t.desc, size: 12, lineHeight: 1.3, color: PM.Colors.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
            .pmCard()
            .overlay(alignment: .topTrailing) {
                if t.pro {
                    Text("PRO")
                        .font(.pm(12, .heavy))
                        .tracking(0.6)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .overlay(Capsule().strokeBorder(PM.Colors.badgeOutline, lineWidth: 1))
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                }
            }
        }
        .buttonStyle(.pmPress)
        .accessibilityLabel("\(t.id.capitalized): \(t.desc)\(t.pro ? ", Pro" : "")")
    }

    private func sectionHeader(_ title: String, seeAll: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .pmHeadlineStyle()
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let seeAll {
                Button("See all", action: seeAll)
                    .font(.pm(15, .semibold))
                    .foregroundStyle(PM.Colors.accent)
            }
        }
    }

    // MARK: Recent measurement

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Most recent record; the earliest-listed wins a tie.
    private var recentRecord: MeasurementRecord? {
        store.measurements.reduce(nil) { best, m in
            guard let best else { return m }
            return m.date > best.date ? m : best
        }
    }

    @ViewBuilder private var recent: some View {
        if let m = recentRecord {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Recent measurement")
                Button { router.select(.history) } label: {
                    HStack(spacing: 14) {
                        PMIcon(m.tool.icon, size: 22)
                            .foregroundStyle(m.source == .arDerived ? PM.Colors.measuring : PM.Colors.accent)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PM.Colors.iconWell))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.name)
                                .font(.pm(15, .semibold))
                                .foregroundStyle(PM.Colors.textPrimary)
                            BoardWrapText(recentMeta(m), size: 12, color: PM.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(m.value)
                            .font(.pm(22, .medium))
                            .monospacedDigit()
                            .foregroundStyle(PM.Colors.textPrimary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .pmCard()
                }
                .buttonStyle(.pmPress)
            }
        }
    }

    private func recentMeta(_ m: MeasurementRecord) -> String {
        var parts = [m.source.rawValue]
        if let p = store.project(m.projectID) { parts.append(p.name) }
        parts.append(Self.timeFormatter.string(from: m.date))
        return Self.metaLine(parts)
    }

    /// "A · B · C" that only breaks after a separator, like the board's nowrap spans.
    static func metaLine(_ parts: [String]) -> String {
        let nb = parts.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
        return nb.enumerated().map { $0.offset < nb.count - 1 ? $0.element + "\u{00A0}·" : $0.element }
            .joined(separator: " ")
    }

    // MARK: Projects

    private static let dashedOutline = Color(dark: 0x313A40, light: 0xC9CFCB)

    private var projects: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Projects") { router.select(.projects) }
            HStack(alignment: .top, spacing: 12) {
                if let p = store.projects.first {
                    projectCard(p)
                }
                Button { router.select(.projects) } label: {
                    VStack(spacing: 12) {
                        PMIcon(.plus, size: 20, stroke: 2.2)
                            .foregroundStyle(PM.Colors.accent)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(PM.Colors.iconWell))
                        Text("New project")
                            .font(.pm(14, .semibold))
                            .foregroundStyle(PM.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: PM.Radius.card, style: .continuous)
                        .fill(PM.Colors.surface.opacity(0.4)))
                    .overlay(
                        RoundedRectangle(cornerRadius: PM.Radius.card, style: .continuous)
                            .strokeBorder(Self.dashedOutline, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: PM.Radius.card, style: .continuous))
                }
                .buttonStyle(.pmPress)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func projectCard(_ p: Project) -> some View {
        let count = store.measurements(in: p).count
        return Button { router.push(.project(projectID: p.id)) } label: {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    KitchenScene()
                        .frame(width: geo.size.width * 1.2, height: 122)
                        .offset(x: -geo.size.width * 0.1, y: -22)
                }
                .frame(height: 84)
                .background(Color(hex: 0x1E262B))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name)
                        .font(.pm(15, .semibold))
                        .foregroundStyle(PM.Colors.textPrimary)
                    BoardWrapText(Self.metaLine(["\(count) measurement\(count == 1 ? "" : "s")",
                                                 "\(p.photoCount) photo\(p.photoCount == 1 ? "" : "s")"]),
                                  size: 12, color: PM.Colors.textSecondary)
                }
                .padding(.horizontal, 6)
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 14, trailing: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .pmCard()
        }
        .buttonStyle(.pmPress)
    }

    // MARK: Promotions

    private var recommended: some View {
        Button { router.push(ProGate.route(.room, pro: true)) } label: {
            HStack(spacing: 14) {
                PMIcon(.room, size: 22)
                    .foregroundStyle(PM.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PM.Colors.freeBadgeFill))
                VStack(alignment: .leading, spacing: 3) {
                    Text("RECOMMENDED").pmCaptionStyle(color: PM.Colors.accent)
                    Text("Measure a whole room")
                        .font(.pm(15, .semibold))
                        .foregroundStyle(PM.Colors.textPrimary)
                    BoardWrapText("Room Measure draws a floor plan for your project.", size: 13, color: PM.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PMIcon(.chevronRight, size: 18, stroke: 1.7)
                    .foregroundStyle(PM.Colors.textSecondary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .pmCard(fill: PM.Colors.recommendedFill, border: PM.Colors.recommendedBorder)
        }
        .buttonStyle(.pmPress)
    }

    private var freePlan: some View {
        Button { router.push(.paywall) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Free plan")
                        .font(.pm(15, .semibold))
                        .foregroundStyle(PM.Colors.textPrimary)
                    BoardWrapText("All core tools included. AR, Projects and Reports with Pro.", size: 13, color: PM.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("See Pro")
                    .font(.pm(14, .bold))
                    .foregroundStyle(PM.Colors.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .overlay(Capsule().strokeBorder(PM.Colors.accent, lineWidth: 1))
                    .fixedSize()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .pmCard()
        }
        .buttonStyle(.pmPress)
    }
}

#Preview {
    RootView()
}

// MARK: - Mini dial (light Home)

/// 126 pt dial on the light Home card: 3 pt rim, crosshair, dashed tolerance ring, 18 pt bubble.
struct HomeMiniDial: View {
    /// Offset in the big dial's points; scaled to this dial.
    var bubbleOffset: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let k: CGFloat = 0.4
        // Board: 120 pt content box + 3 pt border = 126 outer; children are placed inside the border.
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: Color(hex: 0xEEF0EC), location: 0.75)],
                                     center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 103))
                .overlay(Circle().inset(by: 3).stroke(Color(hex: 0x0E1113, opacity: 0.08), lineWidth: 4).blur(radius: 3).offset(y: 2).clipShape(Circle()))
                .overlay(Circle().strokeBorder(Color(hex: 0xC9CFCB), lineWidth: 3))
                .frame(width: 126, height: 126)
            Rectangle().fill(Color(hex: 0xD5DAD6)).frame(width: 1, height: 94).offset(x: 62, y: 13)
            Rectangle().fill(Color(hex: 0xD5DAD6)).frame(width: 94, height: 1).offset(x: 13, y: 62)
            Circle().strokeBorder(PM.Colors.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 27, height: 27).offset(x: 48, y: 48)
            Circle()
                .fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: Color(hex: 0x1FA877), location: 0.45),
                                             .init(color: Color(hex: 0x007A55), location: 1)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 17))
                .frame(width: 18, height: 18)
                .offset(x: 52.5 + bubbleOffset.width * k, y: 52.5 + bubbleOffset.height * k)
                .animation(reduceMotion ? .linear(duration: 0.2) : PM.Motion.bubbleSpring, value: bubbleOffset)
        }
        .frame(width: 126, height: 126, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// MARK: - Text that wraps like the boards

/// Multi-line label that breaks lines greedily, like the browser that drew the boards.
/// SwiftUI `Text` avoids one-word last lines ("push out"), which moves words onto the next line.
/// Used by Home, Tools, Onboarding and Calibration copy that must wrap exactly as drawn.
struct BoardWrapText: UIViewRepresentable {
    var text: String
    var size: CGFloat
    var weight: UIFont.Weight = .regular
    var tracking: CGFloat = 0
    /// CSS line-height multiple; nil keeps the font's natural line height.
    var lineHeight: CGFloat?
    var alignment: NSTextAlignment = .natural
    var color: Color

    init(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, tracking: CGFloat = 0,
         lineHeight: CGFloat? = nil, alignment: NSTextAlignment = .natural, color: Color) {
        self.text = text
        self.size = size
        self.weight = weight
        self.tracking = tracking
        self.lineHeight = lineHeight
        self.alignment = alignment
        self.color = color
    }

    func makeUIView(context: Context) -> UILabel {
        let l = UILabel()
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        l.lineBreakStrategy = []
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        l.setContentHuggingPriority(.defaultHigh, for: .vertical)
        l.isAccessibilityElement = true
        return l
    }

    func updateUIView(_ l: UILabel, context: Context) {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let p = NSMutableParagraphStyle()
        p.alignment = alignment
        p.lineBreakMode = .byWordWrapping
        p.lineBreakStrategy = []
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font, .kern: tracking, .foregroundColor: UIColor(color), .paragraphStyle: p,
        ]
        if let lineHeight {
            let lh = (size * lineHeight).rounded()
            p.minimumLineHeight = lh
            p.maximumLineHeight = lh
            attrs[.baselineOffset] = (lh - font.lineHeight) / 2
        }
        l.attributedText = NSAttributedString(string: text, attributes: attrs)
        l.accessibilityLabel = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let fit = uiView.sizeThatFits(CGSize(width: width.isFinite ? width : 10_000, height: .greatestFiniteMagnitude))
        let hug = alignment == .natural || alignment == .left
        let w = width.isFinite ? (hug ? min(fit.width, width) : width) : fit.width
        return CGSize(width: w, height: ceil(fit.height))
    }
}
