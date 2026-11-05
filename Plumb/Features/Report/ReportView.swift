//
//  ReportView.swift
//  Plumb
//
//  PDF report board (A4, 794 x 1123 pt). The same `ReportPage` view is shown scaled on screen
//  and rendered to PDF with ImageRenderer for sharing. Always light paper.
//

import SwiftUI

struct ReportView: View {
    var projectID: UUID

    @Environment(MeasurementStore.self) private var store
    @State private var pdfURL: URL?
    @State private var renderFailed = false

    var body: some View {
        VStack(spacing: 0) {
            PMTopBar(title: "PDF Report") {
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        PMIcon(.share, size: 20, stroke: 1.8)
                            .foregroundStyle(PM.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(PM.Colors.surface))
                            .overlay(Circle().strokeBorder(PM.Colors.border, lineWidth: 1))
                    }
                    .accessibilityLabel("Share PDF")
                } else {
                    TopBarPlaceholder()
                }
            }

            if let content = ReportContent(projectID: projectID, store: store) {
                GeometryReader { geo in
                    let width = geo.size.width - 32
                    let scale = width / ReportPage.size.width
                    let pages = ReportLayout.pages(for: content)
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(pages.indices, id: \.self) { i in
                                ReportPage(content: content, spec: pages[i])
                                    .scaleEffect(scale, anchor: .topLeading)
                                    .frame(width: width, height: ReportPage.size.height * scale, alignment: .topLeading)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("Report page \(i + 1) of \(pages.count)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        // Button (54) + its bottom inset (8) + scrim fade (32) + breathing room,
                        // so the last page scrolls fully clear of the floating Share PDF button.
                        .padding(.bottom, 120)
                    }
                    .scrollIndicators(.hidden)
                }
                .overlay(alignment: .bottom) {
                    Group {
                        if let pdfURL {
                            ShareLink(item: pdfURL) {
                                HStack(spacing: 8) {
                                    PMIcon(.share, size: 18, stroke: 2)
                                    Text("Share PDF")
                                }
                            }
                            .buttonStyle(.pmPrimary)
                        } else {
                            Button {} label: { Text("Preparing PDF\u{2026}") }
                                .buttonStyle(.pmPrimary)
                                .disabled(true)
                                .opacity(0.6)
                        }
                    }
                    .padding(.horizontal, PM.Space.gutter)
                    .padding(.top, 32)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    // Scrim: background colour fading up so pages never sit directly under the button.
                    .background(
                        LinearGradient(stops: [
                            .init(color: PM.Colors.background.opacity(0), location: 0),
                            .init(color: PM.Colors.background.opacity(0.92), location: 0.45),
                            .init(color: PM.Colors.background, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                    )
                }
                .task(id: content.signature) {
                    pdfURL = nil
                    pdfURL = ReportRenderer.render(content)
                    renderFailed = pdfURL == nil
                }
                .alert("Couldn\u{2019}t create the PDF", isPresented: $renderFailed) {
                    Button("Try again") {
                        pdfURL = ReportRenderer.render(content)
                        renderFailed = pdfURL == nil
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Your \(Device.name) may be low on storage. Free up some space and try again.")
                }
            } else {
                Spacer()
                Text("This project no longer exists.")
                    .font(.pm(15))
                    .foregroundStyle(PM.Colors.textSecondary)
                Spacer()
            }
        }
        .background(PM.Colors.background.ignoresSafeArea())
    }
}

// MARK: - Content

struct ReportContent {
    struct Row: Hashable {
        var name: String
        var value: String
        var method: String
        var time: String
    }

    var projectName: String
    var date: String
    var itemsText: String
    var rows: [Row]
    var photos: ReportPhotoSet
    var note: String?

    var hasPhotos: Bool {
        if case .none = photos { return false }
        return true
    }

    init?(projectID: UUID, store: MeasurementStore) {
        guard let project = store.project(projectID) else { return nil }
        let summary = ProjectSummary(project, store: store)
        projectName = project.name
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "d MMM yyyy"
        date = f.string(from: Date())
        itemsText = summary.countsText
        rows = store.items(in: projectID).map {
            Row(name: $0.name, value: $0.value, method: Self.method($0), time: HistoryTime.string($0.date))
        }
        let name = project.name.lowercased()
        // The illustrated photos and note are the board's sample content: debug design review only.
        // Real projects carry no photo files yet, so Release reports list measurements only.
        var sample = false
        #if DEBUG
        sample = DebugLaunch.isActive
        #endif
        if !sample || project.photoCount == 0 {
            photos = .none
        } else if name.contains("kitchen") {
            photos = .kitchen
        } else if name.contains("bathroom") {
            photos = .bathroom(caption: rows.first.map { "\($0.name), \($0.method)" } ?? "Photo")
        } else {
            photos = .none
        }
        // Sample note from the board for the sample project.
        note = sample && name.contains("kitchen")
            ? "Confirm the counter height against the cabinet supplier\u{2019}s drawing before ordering."
            : nil
    }

    /// Changes whenever anything shown on the page changes, so the PDF is re-rendered.
    var signature: String {
        ([projectName, date, itemsText, note ?? ""] + rows.map { "\($0.name)|\($0.value)|\($0.time)" }).joined(separator: "#")
    }

    private static func method(_ m: MeasurementRecord) -> String {
        if m.source == .userEntered { return "User-entered" }
        switch m.tool {
        case .ar: return "AR Measure"
        case .room: return "Room Measure"
        case .photo: return "Photo Measure"
        case .ruler: return "Ruler (screen)"
        case .compass: return "Sensor (heading)"
        case .calculator: return "Calculator"
        case .converter: return "Unit Converter"
        case .level, .surface, .angle, .protractor, .slope: return "Sensor (device motion)"
        }
    }
}

enum ReportPhotoSet {
    case none
    case kitchen
    case bathroom(caption: String)
}

// MARK: - Page

private enum ReportInk {
    static let ink = PM.Colors.reportInk
    static let secondary = PM.Colors.reportSecondary
    static let rule = PM.Colors.reportRule
    static let line = PM.Colors.reportTableLine
}

/// Which part of the report a page carries.
struct ReportPageSpec: Hashable {
    var index: Int
    var count: Int
    var rows: Range<Int>
    var showsPhotos: Bool
    var showsNotes: Bool
}

/// Splits a report into A4 pages using the board's measured heights, so long projects never clip.
enum ReportLayout {
    static let contentHeight: CGFloat = 1123 - 56 - 48
    static let gap: CGFloat = 26
    static let header: CGFloat = 61
    static let meta: CGFloat = 46
    static let continuedHeader: CGFloat = 61
    static let tableTitleAndHead: CGFloat = 22 + 10 + 39
    static let row: CGFloat = 46
    static let photos: CGFloat = 22 + 10 + 200 + 8 + 17
    static let footer: CGFloat = 15 + 40 + 10 + 16

    static func notes(_ note: String?) -> CGFloat {
        guard let note else { return 0 }
        let lines = max(1, Int((Double(note.count + 12) / 78).rounded(.up)))
        return 22 + 8 + CGFloat(lines) * 25
    }

    static func pages(for c: ReportContent) -> [ReportPageSpec] {
        let photoH = c.hasPhotos ? photos + gap : 0
        let notesH = c.note == nil ? 0 : notes(c.note) + gap
        var specs: [(Range<Int>, Bool)] = []
        var start = 0
        var first = true
        repeat {
            let top = first ? header + gap + meta + gap : continuedHeader + gap
            let avail = contentHeight - top - footer - gap - tableTitleAndHead
            let fit = max(1, Int(avail / row))
            let end = min(c.rows.count, start + fit)
            specs.append((start..<end, first))
            start = end
            first = false
        } while start < c.rows.count
        // Photos and notes go after the last rows, on that page if they fit, else on a page of their own.
        var result = specs.enumerated().map { i, s in
            ReportPageSpec(index: i, count: 0, rows: s.0, showsPhotos: false, showsNotes: false)
        }
        if photoH + notesH > 0 {
            let last = result.count - 1
            let top = last == 0 ? header + gap + meta + gap : continuedHeader + gap
            let used = top + tableTitleAndHead + CGFloat(result[last].rows.count) * row + gap
            if used + photoH + notesH + footer <= contentHeight {
                result[last].showsPhotos = c.hasPhotos
                result[last].showsNotes = c.note != nil
            } else {
                result.append(ReportPageSpec(index: result.count, count: 0, rows: c.rows.count..<c.rows.count,
                                             showsPhotos: c.hasPhotos, showsNotes: c.note != nil))
            }
        }
        let n = result.count
        return result.map { var p = $0; p.count = n; return p }
    }
}

/// One A4 page drawn at 1 pt = 1 CSS px.
struct ReportPage: View {
    static let size = CGSize(width: 794, height: 1123)
    var content: ReportContent
    var spec: ReportPageSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if spec.index == 0 {
                header
                meta
            } else {
                continuedHeader
            }
            if !spec.rows.isEmpty || content.rows.isEmpty && spec.index == 0 { measurements }
            if spec.showsPhotos { photos }
            if spec.showsNotes, let note = content.note { notes(note) }
            Spacer(minLength: 0)
            footer
        }
        .padding(.top, 56)
        .padding(.horizontal, 64)
        .padding(.bottom, 48)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(ReportInk.ink)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 12) {
                SVGStroke(d: PMIconName.levelPlain.d, size: 24, lineWidth: 1.8)
                    .foregroundStyle(Color(hex: 0x52F2B8))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ReportInk.ink))
                Text("PLUMB")
                    .font(.pm(20, .heavy))
                    .tracking(3)
            }
            Spacer()
            Text("Measurement report")
                .font(.pm(16))
                .foregroundStyle(ReportInk.secondary)
        }
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) { ReportInk.rule.frame(height: 3) }
    }

    private var continuedHeader: some View {
        HStack(alignment: .bottom) {
            Text(content.projectName).font(.pm(20, .bold)).lineLimit(1)
            Spacer()
            Text("Measurement report, continued")
                .font(.pm(16))
                .foregroundStyle(ReportInk.secondary)
        }
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) { ReportInk.line.frame(height: 1) }
    }

    private var meta: some View {
        HStack(alignment: .top, spacing: 16) {
            metaCell("PROJECT") { Text(content.projectName).font(.pm(22, .bold)) }
            metaCell("DATE") { Text(content.date).font(.pm(22, .semibold)) }
            metaCell("ITEMS") {
                Text(content.itemsText).font(.pm(17, .semibold)).lineLimit(1).fixedSize()
            }
        }
    }

    private func metaCell<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.pm(12, .bold)).tracking(1.2).foregroundStyle(ReportInk.secondary)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Column widths measured from the board's table (666 pt wide).
    private let colItem: CGFloat = 177
    private let colValue: CGFloat = 112
    private let colMethod: CGFloat = 252

    private var measurements: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Measurements").font(.pm(18, .bold))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    th("ITEM").frame(width: colItem, alignment: .leading)
                    th("VALUE").frame(width: colValue, alignment: .trailing)
                    th("METHOD").frame(width: colMethod, alignment: .leading)
                    th("TIME").frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay(alignment: .bottom) { ReportInk.ink.frame(height: 1.5) }

                if content.rows.isEmpty {
                    Text("No measurements in this project yet.")
                        .font(.pm(16))
                        .foregroundStyle(ReportInk.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(content.rows[spec.rows].enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 0) {
                        Text(r.name).font(.pm(16, .semibold))
                            .padding(12).frame(width: colItem, alignment: .leading)
                        Text(r.value).font(.pm(18, .semibold)).monospacedDigit()
                            .padding(12).frame(width: colValue, alignment: .trailing)
                        Text(r.method).font(.pm(16)).foregroundStyle(ReportInk.secondary)
                            .padding(12).frame(width: colMethod, alignment: .leading)
                        Text(r.time).font(.pm(16)).monospacedDigit().foregroundStyle(ReportInk.secondary)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .lineLimit(1)
                    .overlay(alignment: .bottom) { ReportInk.line.frame(height: 1) }
                }
            }
        }
    }

    private func th(_ s: String) -> some View {
        Text(s)
            .font(.pm(13, .bold))
            .tracking(1)
            .foregroundStyle(ReportInk.secondary)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
    }

    @ViewBuilder private var photos: some View {
        switch content.photos {
        case .none:
            EmptyView()
        case .kitchen:
            photoSection {
                ReportFigure(caption: "Kitchen width, AR Measure") {
                    ReportKitchenPhoto(sceneOffset: CGPoint(x: 0, y: -10), sceneSize: CGSize(width: 325, height: 170), floorTop: 160)
                    ReportAnnotation(label: "4.82 m", start: CGPoint(x: 31, y: 90), end: CGPoint(x: 299, y: 90),
                                     labelOrigin: CGPoint(x: 132, y: 58))
                }
                ReportFigure(caption: "Counter height, AR Measure") {
                    ReportKitchenPhoto(sceneOffset: CGPoint(x: -100, y: -116), sceneSize: CGSize(width: 520, height: 286), floorTop: 170)
                    ReportAnnotation(label: "0.91 m", start: CGPoint(x: 161, y: 51), end: CGPoint(x: 161, y: 171),
                                     labelOrigin: CGPoint(x: 172, y: 98))
                }
            }
        case .bathroom(let caption):
            photoSection {
                ReportFigure(caption: caption) {
                    BathroomScene().frame(width: 325, height: 200)
                }
                Color.clear.frame(height: 1)
            }
        }
    }

    private func photoSection<C: View>(@ViewBuilder _ figures: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos and annotations").font(.pm(18, .bold))
            HStack(alignment: .top, spacing: 16) { figures() }
        }
    }

    private func notes(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").font(.pm(18, .bold))
            Text("\(note) \(Text("(User note)").foregroundStyle(ReportInk.secondary))")
                .foregroundStyle(ReportInk.ink)
                .font(.pm(16))
                .lineSpacing(5.8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Measurements are generated using supported device sensors, camera/AR tracking, and user-provided reference data where applicable. Not a certified survey.")
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Generated by Plumb")
                Spacer()
                Text("Page \(spec.index + 1) of \(spec.count)")
            }
        }
        .font(.pm(13))
        .foregroundStyle(ReportInk.secondary)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { ReportInk.line.frame(height: 1) }
    }
}

// MARK: - Figures

/// 325 x 200 photo frame, radius 10, with a caption below.
private struct ReportFigure<Photo: View>: View {
    var caption: String
    @ViewBuilder var photo: () -> Photo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) { photo() }
                .frame(width: 325, height: 200, alignment: .topLeading)
                .background(Color(hex: 0xEEF1EF))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ReportInk.line, lineWidth: 1))
            Text(caption).font(.pm(14)).foregroundStyle(ReportInk.secondary)
        }
    }
}

/// Kitchen scene positioned as on the board, with the perspective floor strip under it.
private struct ReportKitchenPhoto: View {
    var sceneOffset: CGPoint
    var sceneSize: CGSize
    var floorTop: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            KitchenScene()
                .frame(width: sceneSize.width, height: sceneSize.height)
                .offset(x: sceneOffset.x, y: sceneOffset.y)
            ReportFloor()
                .frame(width: 325, height: 200 - floorTop)
                .offset(y: floorTop)
        }
        .frame(width: 325, height: 200, alignment: .topLeading)
    }
}

/// Floor boards receding to a vanishing point above the strip, as drawn on the Report board.
private struct ReportFloor: View {
    private static let rows: [CGFloat] = [0.31, 0.4725, 0.575, 0.6425, 0.6925, 0.73, 0.76, 0.7825,
                                          0.8025, 0.8175, 0.8325, 0.845, 0.855, 0.8625]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0xADA290), Color(hex: 0xBFB4A3)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            for (i, r) in Self.rows.enumerated() {
                ctx.fill(Path(CGRect(x: 0, y: h * r, width: w, height: 2)),
                         with: .color(Color(red: 70 / 255, green: 58 / 255, blue: 44 / 255, opacity: 0.14 + 0.02 * Double(i))))
            }
            let vanish = CGPoint(x: w / 2, y: -1.1 * h)
            var rays = Path()
            for k in 0...20 {
                rays.move(to: vanish)
                rays.addLine(to: CGPoint(x: w / 2 - 10 + CGFloat(k - 10) * 64, y: h))
            }
            ctx.stroke(rays, with: .color(Color(red: 70 / 255, green: 58 / 255, blue: 44 / 255, opacity: 0.26)), lineWidth: 2)
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(stops: [
                        .init(color: Color(red: 25 / 255, green: 22 / 255, blue: 18 / 255, opacity: 0.4), location: 0),
                        .init(color: Color(red: 25 / 255, green: 22 / 255, blue: 18 / 255, opacity: 0), location: 0.26),
                        .init(color: Color.white.opacity(0.05), location: 0.8),
                        .init(color: Color.black.opacity(0.15), location: 1),
                     ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        }
    }
}

/// Green dimension line with haloed endpoints and a value tag.
private struct ReportAnnotation: View {
    var label: String
    var start: CGPoint
    var end: CGPoint
    var labelOrigin: CGPoint

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in p.move(to: start); p.addLine(to: end) }
                .stroke(Color.white, lineWidth: 5)
            Path { p in p.move(to: start); p.addLine(to: end) }
                .stroke(ReportInk.rule, lineWidth: 2)
            ForEach(Array([start, end].enumerated()), id: \.offset) { _, pt in
                Circle()
                    .fill(ReportInk.rule)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .offset(x: pt.x - 5, y: pt.y - 5)
            }
            Text(label)
                .font(.pm(14, .bold))
                .foregroundStyle(.white)
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(ReportInk.rule))
                .offset(x: labelOrigin.x, y: labelOrigin.y)
        }
        .frame(width: 325, height: 200, alignment: .topLeading)
    }
}

// MARK: - PDF

enum ReportRenderer {
    /// Renders every page to an A4 PDF (vector text) in the temporary directory.
    static func render(_ content: ReportContent) -> URL? {
        StorageGuard.retrying { renderOnce(content) }
    }

    private static func renderOnce(_ content: ReportContent) -> URL? {
        let pages = ReportLayout.pages(for: content)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        var safeName = String(content.projectName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespaces)
        if safeName.isEmpty { safeName = "Project" }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName.prefix(60)) report.pdf")
        try? FileManager.default.removeItem(at: url)
        var box = CGRect(origin: .zero, size: ReportPage.size)
        let info: [CFString: Any] = [kCGPDFContextTitle: "\(content.projectName) measurement report",
                                     kCGPDFContextCreator: "Plumb"]
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return nil }
        for spec in pages {
            let renderer = ImageRenderer(content: ReportPage(content: content, spec: spec))
            renderer.proposedSize = ProposedViewSize(ReportPage.size)
            pdf.beginPDFPage(nil)
            renderer.render { _, draw in draw(pdf) }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return size > 0 ? url : nil
    }
}
