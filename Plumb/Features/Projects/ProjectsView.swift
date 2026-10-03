//
//  ProjectsView.swift
//  Plumb
//
//  Projects board, phone 1: featured project card, compact project rows and a dashed "New project" tile.
//

import SwiftUI

struct ProjectsView: View {
    @Environment(MeasurementStore.self) private var store
    @Environment(Router.self) private var router

    @State private var naming = false
    @State private var newName = ""
    @State private var renaming: Project?
    @State private var deleting: Project?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Projects").pmTitleStyle().accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { startNewProject() } label: {
                        PMIcon(.plus, size: 20, stroke: 2.2)
                            .foregroundStyle(PM.Colors.onAccent)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(PM.Colors.accent))
                    }
                    .buttonStyle(.pmPress)
                    .accessibilityLabel("New project")
                }

                Text("Group measurements, photos and reports by real-world job.")
                    .font(.pm(15))
                    .foregroundStyle(PM.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                    Button {
                        router.push(.project(projectID: project.id))
                    } label: {
                        if index == 0 {
                            ProjectFeaturedCard(project: project, summary: ProjectSummary(project, store: store))
                        } else {
                            ProjectCompactRow(project: project, summary: ProjectSummary(project, store: store))
                        }
                    }
                    .buttonStyle(.pmPress)
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { startRename(project) }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = project }
                    }
                    .accessibilityAction(named: "Rename") { startRename(project) }
                    .accessibilityAction(named: "Delete") { deleting = project }
                }

                if store.projects.isEmpty {
                    Text("No projects yet. Create one for each real-world job, then save measurements, photos and reports to it.")
                        .font(.pm(15))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { startNewProject() } label: {
                    HStack(spacing: 12) {
                        PMIcon(.plus, size: 18, stroke: 2.2)
                            .foregroundStyle(PM.Colors.accent)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(PM.Colors.iconWell))
                        Text("New project")
                            .font(.pm(15, .semibold))
                            .foregroundStyle(PM.Colors.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(PM.Colors.surface.opacity(0.4)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(ProjectPalette.dashedBorder, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pmPress)
            }
            .padding(.top, 62 + 1 - PM.Board.statusBar)
            .padding(.horizontal, PM.Space.gutter)
            .padding(.bottom, PMTabBar.visibleHeight + 22)
        }
        .scrollIndicators(.hidden)
        .background(PM.Colors.background.ignoresSafeArea())
        .alert("Rename project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Project name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let p = renaming { store.renameProject(p.id, to: newName) } }
        }
        .confirmationDialog(deleting.map { "Delete \u{201C}\($0.name)\u{201D} and its measurements?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete project", role: .destructive) {
                if let p = deleting { withAnimation(PM.Motion.normal) { store.deleteProject(p.id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert("New project", isPresented: $naming) {
            TextField("Project name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createProject() }
        } message: {
            Text("Name the real-world job, for example \u{201C}Laundry shelves\u{201D}.")
        }
    }

    private func startNewProject() {
        newName = ""
        naming = true
    }

    private func startRename(_ p: Project) {
        newName = p.name
        renaming = p
    }

    private func createProject() {
        guard MeasurementStore.cleanName(newName) != nil else { return }
        let project = store.addProject(named: newName)
        router.push(.project(projectID: project.id))
    }
}

// MARK: - Summary text

/// Counts and labels shared by project cards, project detail and the report.
struct ProjectSummary {
    var measurementCount: Int
    var photoCount: Int
    var updated: Date

    init(_ project: Project, store: MeasurementStore) {
        let items = store.items(in: project.id)
        measurementCount = items.count
        photoCount = project.photoCount
        updated = items.map(\.date).max() ?? project.created
    }

    var measurementsText: String { "\(measurementCount) measurement\(measurementCount == 1 ? "" : "s")" }
    var photosText: String { "\(photoCount) photo\(photoCount == 1 ? "" : "s")" }
    var countsText: String { "\(measurementsText) · \(photosText)" }

    var updatedText: String {
        let cal = Calendar.current
        if cal.isDateInToday(updated) { return "Updated today" }
        if cal.isDateInYesterday(updated) { return "Updated yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "d MMM"
        return "Updated \(f.string(from: updated))"
    }

    var pdfReady: Bool { measurementCount > 0 }
}

enum ProjectPalette {
    static let coverFill = Color(dark: 0x1E262B, light: 0xE6E3DC)
    static let dashedBorder = Color(dark: 0x313A40, light: 0xC9CFCB)
}

/// Illustrated cover for a project: the kitchen and bathroom scenes stand in for the user's photos.
struct ProjectCoverArt: View {
    var project: Project

    var body: some View {
        let name = project.name.lowercased()
        if name.contains("kitchen") {
            KitchenScene()
        } else if name.contains("bathroom") {
            BathroomScene()
        } else {
            ZStack {
                ProjectPalette.coverFill
                PMIcon(.project, size: 28, stroke: 1.7).foregroundStyle(PM.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Cards

/// 150 pt cover with a "PDF ready" chip, then name and counts.
struct ProjectFeaturedCard: View {
    var project: Project
    var summary: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                GeometryReader { geo in
                    ProjectCoverArt(project: project)
                        .frame(width: geo.size.width, height: 184)
                        .offset(y: -34)
                }
                .frame(height: 150)
                .background(ProjectPalette.coverFill)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if summary.pdfReady {
                    HStack(spacing: 6) {
                        PMIcon(.check, size: 12, stroke: 3)
                        Text("PDF ready").font(.pm(12, .bold))
                    }
                    .foregroundStyle(PM.Colors.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(PM.Colors.background))
                    .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.pm(18, .bold))
                    .foregroundStyle(PM.Colors.textPrimary)
                Text("\(summary.countsText) · \(summary.updatedText)")
                    .font(.pm(13))
                    .foregroundStyle(PM.Colors.textSecondary)
            }
            .padding(.horizontal, 8)
            .multilineTextAlignment(.leading)
        }
        .padding(.top, 9)
        .padding(.horizontal, 9)
        .padding(.bottom, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmCard(radius: 26)
        .accessibilityElement(children: .combine)
    }
}

/// 72 pt thumbnail, name, counts and a chevron.
struct ProjectCompactRow: View {
    var project: Project
    var summary: ProjectSummary

    var body: some View {
        HStack(spacing: 14) {
            ProjectCoverArt(project: project)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.pm(16, .bold))
                    .foregroundStyle(PM.Colors.textPrimary)
                Text(summary.countsText)
                    .font(.pm(13))
                    .foregroundStyle(PM.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PMIcon(.chevronRight, size: 18, stroke: 2).foregroundStyle(PM.Colors.textSecondary)
        }
        .padding(.vertical, 9)
        .padding(.leading, 9)
        .padding(.trailing, 17)
        .pmCard(radius: 22)
        .accessibilityElement(children: .combine)
    }
}
