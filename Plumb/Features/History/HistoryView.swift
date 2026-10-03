//
//  HistoryView.swift
//  Plumb
//
//  History board: day-grouped timeline with filter chips, swipe actions and an empty state.
//

import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(MeasurementStore.self) private var store
    @Environment(Router.self) private var router

    @State private var filter: HistoryFilter = .all
    @State private var openRowID: UUID? = DebugLaunch.is("swiped") ? MeasurementStore.shared.historyItems.first?.id : nil
    @State private var undo: (record: MeasurementRecord, index: Int)?
    @State private var undoTask: Task<Void, Never>?
    @State private var searching = false
    @State private var query = ""
    @State private var savingItem: MeasurementRecord?
    @State private var pendingSave: MeasurementRecord?
    @State private var naming = false
    @State private var newProjectName = ""

    var body: some View {
        Group {
            if store.historyItems.isEmpty {
                HistoryEmptyState { router.push(.level) }
            } else {
                timeline
            }
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let undo {
                UndoToast(text: "Deleted \(undo.record.name)") { restore() }
                    .padding(.bottom, PMTabBar.visibleHeight + 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .confirmationDialog("Save to project", isPresented: Binding(
            get: { savingItem != nil },
            set: { if !$0 { savingItem = nil } }
        ), titleVisibility: .visible, presenting: savingItem) { item in
            ForEach(store.projects) { project in
                Button(project.name) {
                    store.save(item, to: project.id)
                    withAnimation(PM.Motion.normal) { openRowID = nil }
                }
            }
            Button("New project\u{2026}") {
                pendingSave = item
                newProjectName = ""
                naming = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New project", isPresented: $naming) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) { pendingSave = nil }
            Button("Create and save") {
                guard let item = pendingSave, MeasurementStore.cleanName(newProjectName) != nil else { return }
                let p = store.addProject(named: newProjectName)
                store.save(item, to: p.id)
                pendingSave = nil
                withAnimation(PM.Motion.normal) { openRowID = nil }
            }
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if searching { searchField }
                filterChips

                let sections = daySections
                if sections.isEmpty {
                    Text("No measurements match.")
                        .font(.pm(15))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                ForEach(sections, id: \.day) { section in
                    Text(section.title)
                        .pmCaptionStyle(tracking: 1.2)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.items) { item in
                        HistorySwipeRow(
                            item: item,
                            projectName: store.project(item.projectID)?.name,
                            isOpen: Binding(
                                get: { openRowID == item.id },
                                set: { openRowID = $0 ? item.id : nil }
                            ),
                            onOpen: { open(item) },
                            onSave: { savingItem = item },
                            onDelete: { delete(item) }
                        )
                    }
                }

                Text("Swipe left on a measurement to save, share or delete it.")
                    .font(.pm(12))
                    .foregroundStyle(PM.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 62 + 1 - PM.Board.statusBar)
            .padding(.horizontal, PM.Space.gutter)
            .padding(.bottom, PMTabBar.visibleHeight + 22)
        }
        .scrollIndicators(.hidden)
    }

    private func delete(_ item: MeasurementRecord) {
        let index = store.measurements.firstIndex { $0.id == item.id } ?? store.measurements.count
        withAnimation(PM.Motion.normal) {
            openRowID = nil
            store.delete(item)
            undo = (item, index)
        }
        Haptics.selection()
        UIAccessibility.post(notification: .announcement, argument: "Deleted \(item.name). Undo available.")
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(PM.Motion.normal) { undo = nil }
        }
    }

    private func restore() {
        guard let undo else { return }
        undoTask?.cancel()
        withAnimation(PM.Motion.normal) {
            store.restore(undo.record, at: undo.index)
            self.undo = nil
        }
    }

    private var header: some View {
        HStack {
            Text("History").pmTitleStyle().accessibilityAddTraits(.isHeader)
            Spacer()
            IconCircleButton(icon: .search, label: "Search history", stroke: 1.8) {
                withAnimation(PM.Motion.normal) {
                    searching.toggle()
                    if !searching { query = "" }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            PMIcon(.search, size: 18, stroke: 1.8).foregroundStyle(PM.Colors.textSecondary)
            TextField("Search measurements", text: $query)
                .font(.pm(15))
                .foregroundStyle(PM.Colors.textPrimary)
                .submitLabel(.search)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .pmCard(radius: 22)
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases, id: \.self) { f in
                    let on = f == filter
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { filter = f; openRowID = nil }
                    } label: {
                        Text(f.title)
                            .font(.pm(14, .bold))
                            .foregroundStyle(on ? PM.Colors.onThumb : PM.Colors.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 44)
                            .frame(height: 44)
                            .background(Capsule().fill(on ? PM.Colors.thumb : PM.Colors.surfaceRaised))
                            .overlay(Capsule().strokeBorder(on ? PM.Colors.thumb : PM.Colors.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: Data

    private struct DaySection {
        var day: Date
        var title: String
        var items: [MeasurementRecord]
    }

    private var daySections: [DaySection] {
        let cal = Calendar.current
        let items = store.historyItems.filter { item in
            filter.matches(item) && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
        let grouped = Dictionary(grouping: items) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            DaySection(day: day, title: Self.dayTitle(day), items: grouped[day] ?? [])
        }
    }

    private static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: day).uppercased()
    }

    private func open(_ item: MeasurementRecord) {
        if openRowID != nil {
            withAnimation(PM.Motion.normal) { openRowID = nil }
            return
        }
        if let id = item.projectID {
            router.push(.project(projectID: id))
        } else {
            router.push(item.tool.historyRoute)
        }
    }
}

// MARK: - Filter

enum HistoryFilter: CaseIterable {
    case all, level, distance, angle, area

    var title: String {
        switch self {
        case .all: "All"
        case .level: "Level"
        case .distance: "Distance"
        case .angle: "Angle"
        case .area: "Area"
        }
    }

    func matches(_ m: MeasurementRecord) -> Bool {
        switch self {
        case .all: true
        case .level: m.tool == .level || m.tool == .surface
        case .distance: [.ar, .ruler, .photo].contains(m.tool) && !m.value.contains("²")
        case .angle: [.angle, .protractor, .slope, .compass].contains(m.tool)
        case .area: m.value.contains("²") || m.tool == .room
        }
    }
}

extension ToolKind {
    /// Where a standalone History row opens.
    var historyRoute: Route {
        switch self {
        case .level: .level
        case .surface: .surface
        case .angle: .angle
        case .protractor: .protractor
        case .compass: .compass
        case .ruler: .ruler
        case .ar: .ar
        case .room: .room
        case .photo: .photo
        case .slope: .slope
        case .calculator: .calculators
        case .converter: .converter
        }
    }

    /// Icon tint on History rows: sensor tools are mint, spatial and calculated ones blue.
    var historyTint: Color {
        switch self {
        case .level, .surface, .angle, .protractor, .compass, .slope: PM.Colors.accent
        default: PM.Colors.measuring
        }
    }
}

// MARK: - Row

/// Measurement row with Save / Share / Delete revealed by a left swipe (3 x 64 pt).
struct HistorySwipeRow: View {
    var item: MeasurementRecord
    var projectName: String?
    @Binding var isOpen: Bool
    var onOpen: () -> Void
    var onSave: () -> Void
    var onDelete: () -> Void

    @State private var drag: CGFloat = 0
    private let actionsWidth: CGFloat = 192

    private var offset: CGFloat {
        let base: CGFloat = isOpen ? -actionsWidth : 0
        return min(0, max(-actionsWidth - 40, base + drag))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                HStack(spacing: 0) {
                    action("Save", icon: .project, fill: PM.Colors.accent, text: PM.Colors.onAccent, run: onSave)
                    ShareLink(item: shareText) {
                        actionLabel("Share", icon: .share, fill: PM.Colors.measuring, text: Color(hex: 0x04121A))
                    }
                    .buttonStyle(.plain)
                    action("Delete", icon: .trash, fill: Color(hex: 0xC8322F), text: .white, run: onDelete)
                }
                .frame(width: actionsWidth)
            }

            Button(action: onOpen) {
                HistoryRowContent(item: item, projectName: projectName)
            }
            .buttonStyle(.pmPress)
            .offset(x: offset)
        }
        .background(offset < 0 ? PM.Colors.surfaceRaised : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    drag = v.translation.width
                }
                .onEnded { v in
                    let final = (isOpen ? -actionsWidth : 0) + (drag == 0 ? 0 : v.translation.width)
                    withAnimation(PM.Motion.normal) {
                        isOpen = final < -actionsWidth / 2
                        drag = 0
                    }
                }
        )
        .accessibilityAction(named: "Save to project", onSave)
        .accessibilityAction(named: "Share") { share() }
        .accessibilityAction(named: "Delete", onDelete)
        .contextMenu {
            Button("Save to project", systemImage: "folder", action: onSave)
            ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var shareText: String { "\(item.name): \(item.value) (\(item.source.rawValue))" }

    /// VoiceOver share: presents the system share sheet from the key window.
    private func share() {
        let vc = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        var top = root
        while let p = top?.presentedViewController { top = p }
        top?.present(vc, animated: true)
    }

    private func action(_ title: String, icon: PMIconName, fill: Color, text: Color, run: @escaping () -> Void) -> some View {
        Button(action: run) { actionLabel(title, icon: icon, fill: fill, text: text) }
            .buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, icon: PMIconName, fill: Color, text: Color) -> some View {
        VStack(spacing: 4) {
            PMIcon(icon, size: 18, stroke: 2)
            Text(title).font(.pm(12, .bold))
        }
        .foregroundStyle(text)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(fill)
    }
}

/// Icon well, name, "Source · Project · time" and the value.
struct HistoryRowContent: View {
    var item: MeasurementRecord
    var projectName: String?

    var body: some View {
        HStack(spacing: 14) {
            PMIcon(item.tool.icon, size: 22)
                .foregroundStyle(item.tool.historyTint)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PM.Colors.iconWell))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.pm(15, .semibold))
                    .foregroundStyle(PM.Colors.textPrimary)
                WrapText(meta, size: 12, lineHeight: 1.25, color: PM.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.value)
                .font(.pm(22, .medium))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 15)
        .padding(.horizontal, 17)
        .pmCard(radius: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.value), \(meta)")
    }

    private var meta: String {
        [item.source.rawValue, projectName, HistoryTime.string(item.date)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

enum HistoryTime {
    /// "10:31 AM", as drawn on the boards.
    static func string(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Empty state

struct HistoryEmptyState: View {
    var onStart: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History").pmTitleStyle().accessibilityAddTraits(.isHeader)
                .frame(height: 44)
            VStack(spacing: 24) {
                illustration
                    .offset(y: hover ? -6 : 0)
                VStack(spacing: 8) {
                    Text("No measurements yet")
                        .font(.pm(22, .bold))
                        .foregroundStyle(PM.Colors.textPrimary)
                    WrapText("Measurements you save will appear here, grouped by day.",
                             size: 15, lineHeight: 1.5, alignment: .center, color: PM.Colors.textSecondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                Button(action: onStart) {
                    Text("Take your first measurement")
                        .font(.pm(17, .bold))
                        .foregroundStyle(PM.Colors.onAccent)
                        .padding(.horizontal, 24)
                        .frame(height: 54)
                        .background(Capsule().fill(PM.Colors.accent))
                }
                .buttonStyle(.pmPress)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 62 + 1 - PM.Board.statusBar)
        .padding(.horizontal, PM.Space.gutter)
        .padding(.bottom, PMTabBar.visibleHeight + 22)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { hover = true }
        }
    }

    private var illustration: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    stops: [.init(color: PM.Colors.dialFaceTop, location: 0),
                            .init(color: PM.Colors.dialFaceBottom, location: 0.7)],
                    center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 133.8))
                .overlay(Circle().strokeBorder(PM.Colors.dialRim, lineWidth: 1))
            Circle().strokeBorder(PM.Colors.dialLine, lineWidth: 1).frame(width: 110, height: 110)
            PM.Colors.dialLine.frame(width: 1, height: 126)
            PM.Colors.dialLine.frame(width: 126, height: 1)
            Circle()
                .strokeBorder(PM.Colors.accent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .opacity(0.8)
                .frame(width: 32, height: 32)
            Circle()
                .fill(RadialGradient(
                    stops: [.init(color: .white, location: 0),
                            .init(color: PM.Colors.accent, location: 0.38),
                            .init(color: PM.Colors.accentDeep, location: 1)],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 22.9))
                .frame(width: 24, height: 24)
        }
        .frame(width: 168, height: 168)
        .accessibilityHidden(true)
    }
}

/// "Deleted X · Undo" toast shown for five seconds after deleting from History.
struct UndoToast: View {
    var text: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PMIcon(.trash, size: 16, stroke: 2).foregroundStyle(PM.Colors.textSecondary)
            Text(text)
                .font(.pm(15, .semibold))
                .foregroundStyle(PM.Colors.textPrimary)
                .lineLimit(1)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.pm(15, .bold))
                    .foregroundStyle(PM.Colors.accent)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo delete")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background(Capsule().fill(PM.Colors.surfaceRaised))
        .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .padding(.horizontal, PM.Space.gutter)
    }
}
