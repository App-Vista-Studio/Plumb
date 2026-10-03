//
//  MeasurementStore.swift
//  Plumb
//
//  Projects and measurements, persisted as JSON in Application Support.
//
//  - Every mutation is saved (coalesced to one atomic write per run-loop turn).
//  - A missing file starts an empty store. A corrupt or unreadable file is moved aside
//    (`measurements.corrupt-<timestamp>.json`) and never crashes the app; records that fail
//    to decode individually are skipped and the rest are kept.
//  - Debug design-review launches (`-screen`) use the sample data drawn on the History, Projects and
//    Home boards, in memory only. `-state empty` gives an empty store. Release builds never seed data.
//

import Foundation
import Observation

enum ToolKind: String, Codable, CaseIterable {
    case level, surface, angle, protractor, compass, ruler, ar, room, photo, slope, calculator, converter

    var icon: PMIconName {
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
        case .calculator: .calculator
        case .converter: .converter
        }
    }
}

struct MeasurementRecord: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    /// Display value at honest precision, e.g. "4.82 m", "37.2°".
    var value: String
    var source: SourceKind
    var tool: ToolKind
    var projectID: UUID?
    var date: Date
    /// False for items captured straight into a project; History lists the rest.
    var showsInHistory: Bool = true
}

struct Project: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var photoCount: Int
    var created: Date
}

@Observable
final class MeasurementStore {
    static let shared = MeasurementStore()

    var projects: [Project] { didSet { scheduleSave() } }
    var measurements: [MeasurementRecord] { didSet { scheduleSave() } }

    /// Set when the saved file could not be read and was moved aside on this launch.
    private(set) var recoveredFromCorruptFile = false

    @ObservationIgnored private var persists = true
    @ObservationIgnored private var savePending = false
    @ObservationIgnored private let fileURL: URL

    private init() {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                   ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Plumb", isDirectory: true)
        fileURL = dir.appendingPathComponent("measurements.json")
        projects = []
        measurements = []

        #if DEBUG
        if DebugLaunch.isActive {
            persists = false
            if !DebugLaunch.is("empty") { loadSampleData() }
            return
        }
        #endif

        load()
    }

    // MARK: Queries

    func measurements(in project: Project) -> [MeasurementRecord] {
        measurements.filter { $0.projectID == project.id }.sorted { $0.date > $1.date }
    }

    func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    /// Items in a project in capture order (project detail, PDF report).
    func items(in projectID: UUID) -> [MeasurementRecord] {
        measurements.filter { $0.projectID == projectID }
    }

    /// History timeline entries, newest first.
    var historyItems: [MeasurementRecord] {
        measurements.filter(\.showsInHistory).sorted { $0.date > $1.date }
    }

    var mostRecent: MeasurementRecord? { measurements.max { $0.date < $1.date } }

    // MARK: Mutations

    func save(_ m: MeasurementRecord, to projectID: UUID) {
        guard let i = measurements.firstIndex(where: { $0.id == m.id }) else { return }
        measurements[i].projectID = projectID
        Haptics.measurementSaved()
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        measurements.removeAll { $0.projectID == id }
    }

    func add(_ m: MeasurementRecord) {
        measurements.append(m)
        Haptics.measurementSaved()
    }

    func delete(_ m: MeasurementRecord) {
        measurements.removeAll { $0.id == m.id }
    }

    /// Puts back a record removed with `delete(_:)` (undo). No-op if it is already present.
    func restore(_ m: MeasurementRecord, at index: Int? = nil) {
        guard !measurements.contains(where: { $0.id == m.id }) else { return }
        if let index, index >= 0, index <= measurements.count {
            measurements.insert(m, at: index)
        } else {
            measurements.append(m)
        }
    }

    @discardableResult
    func addProject(named name: String) -> Project {
        let p = Project(name: Self.cleanName(name) ?? "Untitled project", photoCount: 0, created: Date())
        projects.insert(p, at: 0)
        return p
    }

    /// Renames a project. Empty or whitespace-only names are ignored. Returns true when renamed.
    @discardableResult
    func renameProject(_ id: UUID, to name: String) -> Bool {
        guard let clean = Self.cleanName(name), let i = projects.firstIndex(where: { $0.id == id }) else { return false }
        projects[i].name = clean
        return true
    }

    /// Trims whitespace and limits names to 80 characters; nil when nothing is left.
    static func cleanName(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).joined(separator: " ")
        guard !t.isEmpty else { return nil }
        return String(t.prefix(80))
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var version = 1
        var projects: [Project]
        var measurements: [MeasurementRecord]
    }

    /// Decodes an array element by element, dropping the ones that fail.
    private struct Lossy<T: Decodable>: Decodable {
        var items: [T]
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            var out: [T] = []
            while !c.isAtEnd {
                if let v = try? c.decode(T.self) { out.append(v) } else { _ = try? c.decode(Skip.self) }
            }
            items = out
        }
        /// Accepts any JSON value so the container always advances past a bad element.
        private struct Skip: Decodable { init(from decoder: Decoder) throws {} }
    }

    private struct LossySnapshot: Decodable {
        var projects: Lossy<Project>?
        var measurements: Lossy<MeasurementRecord>?
    }

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snap = try decoder.decode(LossySnapshot.self, from: data)
            let ps = snap.projects?.items ?? []
            let projectIDs = Set(ps.map(\.id))
            // Drop links to projects that no longer exist rather than showing orphans.
            let ms = (snap.measurements?.items ?? []).map { m -> MeasurementRecord in
                var m = m
                if let pid = m.projectID, !projectIDs.contains(pid) { m.projectID = nil; m.showsInHistory = true }
                return m
            }
            persists = false
            projects = ps
            measurements = ms
            persists = true
        } catch {
            moveAsideCorruptFile()
        }
    }

    private func moveAsideCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = fileURL.deletingLastPathComponent().appendingPathComponent("measurements.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: aside)
        recoveredFromCorruptFile = true
    }

    private func scheduleSave() {
        guard persists, !savePending else { return }
        savePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.savePending = false
            self.writeNow()
        }
    }

    /// Writes the store atomically. Failures (for example a full disk) keep the in-memory data.
    func writeNow() {
        guard persists else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Snapshot(projects: projects, measurements: measurements)) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Sample data (debug design review only)

    #if DEBUG
    private func loadSampleData() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(byAdding: DateComponents(day: dayOffset, hour: h, minute: m), to: today) ?? today
        }

        let kitchen = Project(name: "Kitchen Renovation", photoCount: 3, created: at(-3, 9, 0))
        let bathroom = Project(name: "Bathroom tiles", photoCount: 1, created: at(-8, 14, 0))
        projects = [kitchen, bathroom]

        // Order matters: project detail and the PDF report list items in this order.
        // `showsInHistory` reproduces the History board, which shows only standalone captures.
        measurements = [
            MeasurementRecord(name: "Kitchen width", value: "4.82 m", source: .arDerived, tool: .ar, projectID: kitchen.id, date: at(0, 10, 31), showsInHistory: false),
            MeasurementRecord(name: "Kitchen length", value: "3.71 m", source: .arDerived, tool: .ar, projectID: kitchen.id, date: at(0, 10, 34), showsInHistory: false),
            MeasurementRecord(name: "Counter height", value: "0.91 m", source: .arDerived, tool: .ar, projectID: kitchen.id, date: at(0, 10, 38), showsInHistory: false),
            MeasurementRecord(name: "Wall angle", value: "89.8°", source: .sensor, tool: .angle, projectID: kitchen.id, date: at(0, 10, 45), showsInHistory: false),
            MeasurementRecord(name: "AR Distance", value: "2.43 m", source: .arDerived, tool: .ar, projectID: kitchen.id, date: at(0, 10, 31)),
            MeasurementRecord(name: "Area", value: "15.96 m²", source: .calculated, tool: .calculator, projectID: kitchen.id, date: at(-1, 16, 15)),
            MeasurementRecord(name: "Splashback width", value: "2.40 m", source: .arDerived, tool: .ar, projectID: kitchen.id, date: at(-1, 15, 2), showsInHistory: false),
            MeasurementRecord(name: "Benchtop depth", value: "0.60 m", source: .userEntered, tool: .calculator, projectID: kitchen.id, date: at(-1, 14, 40), showsInHistory: false),
            MeasurementRecord(name: "Level", value: "0.1°", source: .sensor, tool: .level, projectID: nil, date: at(0, 10, 42)),
            MeasurementRecord(name: "Angle", value: "37.2°", source: .sensor, tool: .angle, projectID: nil, date: at(0, 9, 58)),
            MeasurementRecord(name: "Shower wall", value: "2.10 m", source: .arDerived, tool: .ar, projectID: bathroom.id, date: at(-8, 14, 20), showsInHistory: false),
            MeasurementRecord(name: "Tile area", value: "4.62 m²", source: .calculated, tool: .calculator, projectID: bathroom.id, date: at(-8, 14, 32), showsInHistory: false),
            MeasurementRecord(name: "Floor fall", value: "1.1°", source: .sensor, tool: .level, projectID: bathroom.id, date: at(-8, 14, 40), showsInHistory: false),
        ]
    }
    #endif
}
