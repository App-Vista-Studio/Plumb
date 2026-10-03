//
//  ProjectDetailView.swift
//  Plumb
//
//  Projects board, phone 2 (dark) and the Light mode board's project detail.
//  Full-bleed cover, overlapping content sheet, stats, measurement list, Export PDF.
//

import SwiftUI

struct ProjectDetailView: View {
    var projectID: UUID

    @Environment(MeasurementStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.colorScheme) private var scheme

    @State private var renaming = false
    @State private var draftName = ""
    @State private var confirmDelete = false
    @State private var choosingAdd = false
    @State private var showAll = false
    @State private var showingPicker = false

    private var isLight: Bool { scheme == .light }

    var body: some View {
        GeometryReader { geo in
            if let project = store.project(projectID) {
                let summary = ProjectSummary(project, store: store)
                ScrollView {
                    VStack(spacing: 0) {
                        cover(project, width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing)
                        content(project, summary: summary)
                            .padding(.top, isLight ? -18 : -24)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                // The overlay already sits below the status bar: board top 56 (dark) / 54 (light).
                .overlay(alignment: .top) { topButtons(project).padding(.top, isLight ? 7 : 9) }
            } else {
                missing
            }
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .alert("Rename project", isPresented: $renaming) {
            TextField("Project name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.renameProject(projectID, to: draftName) }
        }
        .confirmationDialog("Add measurement", isPresented: $choosingAdd, titleVisibility: .visible) {
            Button("Add from History\u{2026}") { showingPicker = true }
            Button("Measure with AR Measure") { router.push(.ar) }
            Button("Measure an angle") { router.push(.angle) }
            Button("Use a calculator") { router.push(.calculators) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingPicker) {
            HistoryPickerSheet(projectID: projectID)
        }
        .confirmationDialog("Delete this project and its measurements?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete project", role: .destructive) {
                router.pop()
                store.deleteProject(projectID)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Cover

    @ViewBuilder
    private func cover(_ project: Project, width: CGFloat) -> some View {
        if isLight && project.name.lowercased().contains("kitchen") {
            ProjectLightKitchenCover()
                .frame(width: width, height: 240)
                .clipped()
        } else {
            ZStack(alignment: .top) {
                ProjectCoverArt(project: project)
                    .frame(width: width, height: 270)
                    .offset(y: -26)
                // Top scrim keeps the status bar and overlay buttons legible over light cover art.
                LinearGradient(stops: [
                    .init(color: Color(hex: 0x060809, opacity: 0.7), location: 0),
                    .init(color: Color(hex: 0x060809, opacity: 0.4), location: 0.45),
                    .init(color: Color(hex: 0x060809, opacity: 0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: 220, alignment: .top)
            .background(ProjectPalette.coverFill)
            .clipped()
        }
    }

    private func topButtons(_ project: Project) -> some View {
        HStack {
            Button { router.pop() } label: {
                PMIcon(.back, size: 20, stroke: isLight ? 1.9 : 2)
                    .modifier(ProjectOverlayCircle(isLight: isLight))
            }
            .buttonStyle(.pmPress)
            .accessibilityLabel("Back to projects")
            Spacer()
            Menu {
                Button("Rename") {
                    draftName = project.name
                    renaming = true
                }
                Button("Export PDF") { router.push(.report(projectID: project.id)) }
                Button("Delete project", role: .destructive) { confirmDelete = true }
            } label: {
                SVGShape(d: PMIconName.more.d)
                    .fill(PM.Colors.textPrimary)
                    .frame(width: 20, height: 20)
                    .modifier(ProjectOverlayCircle(isLight: isLight))
            }
            .accessibilityLabel("Project options")
        }
        .padding(.horizontal, 20)
    }

    // MARK: Content

    private func content(_ project: Project, summary: ProjectSummary) -> some View {
        let items = store.items(in: project.id)
        return VStack(alignment: .leading, spacing: isLight ? 12 : 16) {
            VStack(alignment: .leading, spacing: isLight ? 2 : 4) {
                Text("PROJECT").pmCaptionStyle(tracking: 1.4)
                Text(project.name)
                    .font(.pm(26, isLight ? .heavy : .bold))
                    .tracking(isLight ? -0.4 : 0)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }

            HStack(spacing: 8) {
                statCell { number("\(summary.measurementCount)"); statLabel("Measurements") }
                statCell { number("\(summary.photoCount)"); statLabel("Photos") }
                statCell {
                    HStack(spacing: 6) {
                        PMIcon(.check, size: 14, stroke: isLight ? 2.8 : 3)
                        Text(summary.pdfReady ? (isLight ? "Ready" : "Available") : "Add items")
                            .font(.pm(15, .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(summary.pdfReady ? PM.Colors.accent : PM.Colors.textSecondary)
                    .frame(height: 26)
                    statLabel("PDF report")
                }
            }

            if items.isEmpty {
                Text("No measurements yet. Tap + to measure something for this project.")
                    .font(.pm(15))
                    .foregroundStyle(PM.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .pmCard(radius: isLight ? 20 : 22)
            } else {
                // Long projects show the first four rows and a "Show all" row so Export PDF stays in reach.
                let collapsed = items.count > 5 && !showAll
                let visible = collapsed ? Array(items.prefix(4)) : items
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { i, item in
                        ProjectMeasurementRow(item: item, isLight: isLight)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Move to History", systemImage: "clock.arrow.circlepath") { detach(item) }
                                Button("Delete", systemImage: "trash", role: .destructive) { store.delete(item) }
                            }
                            .accessibilityAction(named: "Move to History") { detach(item) }
                            .accessibilityAction(named: "Delete") { store.delete(item) }
                        if i < visible.count - 1 || collapsed {
                            (isLight ? Color(hex: 0xECEFEB) : PM.Colors.border).frame(height: 1)
                        }
                    }
                    if collapsed {
                        Button {
                            withAnimation(PM.Motion.normal) { showAll = true }
                        } label: {
                            HStack {
                                Text("Show all \(items.count) measurements")
                                    .font(.pm(15, .semibold))
                                    .foregroundStyle(PM.Colors.accent)
                                Spacer()
                                PMIcon(.chevronRight, size: 16, stroke: 2)
                                    .rotationEffect(.degrees(90))
                                    .foregroundStyle(PM.Colors.accent)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
                .pmCard(radius: isLight ? 20 : 22)
                .clipShape(RoundedRectangle(cornerRadius: isLight ? 20 : 22, style: .continuous))
            }

            HStack(spacing: 10) {
                Button { router.push(.report(projectID: project.id)) } label: {
                    HStack(spacing: 8) {
                        SVGStroke(d: isLight ? "M6 3h8l4 4v14H6z M14 3v4h4M9 13h6M9 17h6" : PMIconName.documentLines.d,
                                  size: 18, lineWidth: isLight ? 1.9 : 2)
                        Text("Export PDF")
                    }
                }
                .buttonStyle(.pmPrimary)
                .disabled(!summary.pdfReady)
                .opacity(summary.pdfReady ? 1 : 0.5)

                Button { choosingAdd = true } label: {
                    PMIcon(.plus, size: 20, stroke: 2)
                        .foregroundStyle(PM.Colors.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(isLight ? Color.white : PM.Colors.surfaceRaised))
                        .overlay(Circle().strokeBorder(isLight ? Color(hex: 0xD5DAD6) : PM.Colors.borderStrong, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.pmPress)
                .accessibilityLabel("Add measurement")
            }
        }
        .padding(.top, isLight ? 20 : 22)
        .padding(.horizontal, 20)
        .padding(.bottom, isLight ? 34 : 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .fill(PM.Colors.background)
        )
    }

    private func statCell<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }
            .padding(.vertical, isLight ? 11 : 13)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pmCard(radius: isLight ? 16 : 18)
    }

    private func number(_ s: String) -> some View {
        Text(s)
            .font(.pm(isLight ? 20 : 22, .semibold))
            .monospacedDigit()
            .foregroundStyle(PM.Colors.textPrimary)
    }

    private func statLabel(_ s: String) -> some View {
        Text(s)
            .font(.pm(12))
            .foregroundStyle(PM.Colors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private var missing: some View {
        VStack(spacing: 16) {
            PMTopBar(title: "Project")
            Spacer()
            Text("This project was deleted.")
                .font(.pm(15))
                .foregroundStyle(PM.Colors.textSecondary)
            Button("Back to Projects") { router.select(.projects) }
                .buttonStyle(.pmSecondary)
            Spacer()
        }
    }

    /// Takes a measurement out of the project and back to the History timeline.
    private func detach(_ item: MeasurementRecord) {
        guard let i = store.measurements.firstIndex(where: { $0.id == item.id }) else { return }
        store.measurements[i].projectID = nil
        store.measurements[i].showsInHistory = true
    }
}

// MARK: - Pieces

/// 44 pt circle over the cover, matching `IconCircleButton` (surface fill, 1 pt border),
/// with a blur under a translucent surface tint so it stays legible over the cover art.
private struct ProjectOverlayCircle: ViewModifier {
    var isLight: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(PM.Colors.textPrimary)
            .frame(width: 44, height: 44)
            .background {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(PM.Colors.surface.opacity(isLight ? 0.8 : 0.6))
                }
            }
            .overlay(Circle().strokeBorder(PM.Colors.border, lineWidth: 1))
            .contentShape(Circle())
    }
}

struct ProjectMeasurementRow: View {
    var item: MeasurementRecord
    var isLight: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.pm(15, .semibold))
                    .foregroundStyle(PM.Colors.textPrimary)
                Text(item.source.rawValue)
                    .font(.pm(12, .semibold))
                    .foregroundStyle(Self.tint(item.source))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.value)
                .font(.pm(isLight ? 19 : 20, isLight ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, isLight ? 11 : 13)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    static func tint(_ source: SourceKind) -> Color {
        switch source {
        case .arDerived: PM.Colors.measuring
        case .sensor: PM.Colors.accent
        case .calculated, .userEntered: PM.Colors.textSecondary
        }
    }
}

/// The light-mode kitchen cover from the Light mode board, drawn on its 390 x 240 grid.
struct ProjectLightKitchenCover: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xEFEDE8), Color(hex: 0xE6E3DC)], startPoint: .top, endPoint: .bottom)
            ZStack(alignment: .topLeading) {
                // Pendant lights
                ForEach([150.0, 250.0], id: \.self) { x in
                    Color(hex: 0x9AA39E).frame(width: 2, height: 34).offset(x: x, y: 0)
                    UnevenRoundedRectangle(topLeadingRadius: 15, topTrailingRadius: 15)
                        .fill(Color(hex: 0x2E353A))
                        .frame(width: 30, height: 16)
                        .offset(x: x - 14, y: 34)
                }
                // Upper cabinets
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { _ in lightCabinet(handle: false) }
                }
                .frame(width: 342, height: 52)
                .offset(x: 24, y: 70)
                // Splashback
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF6F5F1)))
                    var x: CGFloat = 21
                    while x < size.width {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color(hex: 0xE4E2DC)))
                        x += 22
                    }
                }
                .frame(width: 342, height: 34)
                .offset(x: 24, y: 126)
                // Benchtop
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0xCFC8BB))
                    .shadow(color: Color(hex: 0xB9B2A5), radius: 0, y: 2)
                    .frame(width: 358, height: 10)
                    .offset(x: 16, y: 160)
                // Lower cabinets
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { _ in lightCabinet(handle: true) }
                }
                .frame(width: 342, height: 44)
                .offset(x: 24, y: 172)
                // Dimension line
                Color(hex: 0x007A55).frame(width: 342, height: 2).offset(x: 24, y: 150)
                Color(hex: 0x007A55).frame(width: 2, height: 14).offset(x: 22, y: 144)
                Color(hex: 0x007A55).frame(width: 2, height: 14).offset(x: 366, y: 144)
                Text("4.82 m")
                    .font(.pm(12, .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(Color(hex: 0x007A55)))
                    .offset(x: 160, y: 138)
            }
            .frame(width: 390, height: 240, alignment: .topLeading)

            // Floor boards, full width
            VStack {
                Spacer()
                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    var clip = Path()
                    clip.move(to: CGPoint(x: w * 0.06, y: 0))
                    clip.addLine(to: CGPoint(x: w * 0.94, y: 0))
                    clip.addLine(to: CGPoint(x: w, y: h))
                    clip.addLine(to: CGPoint(x: 0, y: h))
                    clip.closeSubpath()
                    ctx.clip(to: clip)
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xC7B79E)))
                    var x: CGFloat = 38
                    while x < w {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 2, height: h)), with: .color(Color(hex: 0xBCAB90)))
                        x += 40
                    }
                }
                .frame(height: 24)
            }
        }
        .accessibilityLabel("Kitchen cover illustration")
    }

    private func lightCabinet(handle: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0xD6D9D4), lineWidth: 1))
            .overlay(alignment: .top) {
                if handle {
                    GeometryReader { g in
                        Color(hex: 0x9AA39E)
                            .frame(width: g.size.width * 0.2, height: 2)
                            .offset(x: g.size.width * 0.4, y: 6)
                    }
                }
            }
    }
}

/// Lists History measurements that aren't in this project yet; tap to add.
private struct HistoryPickerSheet: View {
    var projectID: UUID
    @Environment(MeasurementStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var candidates: [MeasurementRecord] {
        store.measurements.filter { $0.projectID != projectID }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Add from History") { dismiss() }
            if candidates.isEmpty {
                Text("Nothing to add yet. Measurements you take appear in History first.")
                    .font(.pm(15))
                    .foregroundStyle(PM.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(candidates) { item in
                            Button {
                                store.save(item, to: projectID)
                            } label: {
                                HistoryRowContent(item: item, projectName: store.project(item.projectID)?.name)
                            }
                            .buttonStyle(.pmPress)
                            .accessibilityHint("Adds it to this project")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(20)
        .background(PM.Colors.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
