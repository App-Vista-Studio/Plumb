//
//  PhotoMeasureView.swift
//  Plumb
//
//  Photo Measure (board 15): annotation editor over a photo, plus the export sheet.
//  The user marks a reference of known length on the photo (lavender) and enters that length.
//  Every other length is scaled from it, so it is "Calculated" and only valid in the reference's plane.
//

import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Model

private enum PhotoTool: String, CaseIterable {
    case line = "Line", arrow = "Arrow", text = "Text", angle = "Angle", rectangle = "Rectangle", circle = "Circle"

    var icon: String {
        switch self {
        case .line: "M5 19L19 5 M4 20a1 1 0 1 0 2 0a1 1 0 1 0-2 0 M18 4a1 1 0 1 0 2 0a1 1 0 1 0-2 0"
        case .arrow: "M5 19L19 5 M11 5h8v8"
        case .text: "M5 6h14 M12 6v13 M9 19h6"
        case .angle: "M4 20h16 M4 20L17 6 M11 20a7 7 0 0 0-2.1-5"
        case .rectangle: "M5 6h14v12H5z"
        case .circle: "M4 12a8 8 0 1 0 16 0a8 8 0 1 0-16 0"
        }
    }

    /// True when the tool produces a number that needs the reference scale.
    var needsScale: Bool { self == .line || self == .rectangle || self == .circle }
}

private enum ExportFormat { case png, pdf }

/// An annotation. Points are normalised to the image (0...1 on each axis).
private struct PhotoAnnotation: Identifiable, Equatable {
    var id = UUID()
    var kind: PhotoTool
    var points: [CGPoint]
    var text: String = ""
}

/// The reference line and its real length (nil until the user enters it).
private struct PhotoReference: Equatable {
    var a: CGPoint
    var b: CGPoint
    var metres: Double?
    var name: String?
}

private struct PhotoDoc: Equatable {
    var image: UIImage?
    /// The board's illustrated hallway (debug captures only).
    var isSample = false
    /// Image size in pixels (or board points for the sample).
    var size: CGSize = CGSize(width: 390, height: 370)
    var reference = PhotoReference(a: CGPoint(x: 0.3, y: 0.35), b: CGPoint(x: 0.7, y: 0.35), metres: nil)
    var annotations: [PhotoAnnotation] = []

    var hasPhoto: Bool { image != nil || isSample }

    static func == (l: PhotoDoc, r: PhotoDoc) -> Bool {
        l.image === r.image && l.isSample == r.isSample && l.size == r.size
            && l.reference == r.reference && l.annotations == r.annotations
    }

    /// Distance in image units between two normalised points.
    func units(_ p: CGPoint, _ q: CGPoint) -> Double {
        Double(hypot((q.x - p.x) * size.width, (q.y - p.y) * size.height))
    }

    /// Metres per image unit, or nil while the reference is unset or degenerate.
    var metresPerUnit: Double? {
        guard let m = reference.metres, m > 0, m.isFinite else { return nil }
        let u = units(reference.a, reference.b)
        guard u > 2 else { return nil }
        return m / u
    }

    static var sample: PhotoDoc {
        let w: CGFloat = 390, h: CGFloat = 370
        func n(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / w, y: y / h) }
        return PhotoDoc(image: nil, isSample: true, size: CGSize(width: w, height: h),
                        reference: PhotoReference(a: n(47, 128), b: n(111, 128), metres: 0.82, name: "door width"),
                        annotations: [PhotoAnnotation(kind: .line, points: [n(140, 262), n(327, 262)])])
    }
}

/// Keeps the open photo and its annotations while the user moves around the app.
@Observable
private final class PhotoSessionStore {
    static let shared = PhotoSessionStore()
    var doc = PhotoDoc()
    var undo: [PhotoDoc] = []
    var redo: [PhotoDoc] = []
    var selected: UUID?
}

private enum PhotoFormat {
    static func metres(_ m: Double) -> String {
        guard m.isFinite else { return "—" }
        return m >= 10 ? String(format: "%.1f m", m) : String(format: "%.2f m", m)
    }

    /// Accepts "0.82" and "0,82"; must be above 0 and at most 1000 m.
    static func parseMetres(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces)
        guard let v = Double(t), v.isFinite, v > 0, v <= 1000 else { return nil }
        return v
    }

    static func angle(_ a: CGPoint, _ v: CGPoint, _ b: CGPoint, size: CGSize) -> Double {
        let ax = Double((a.x - v.x) * size.width), ay = Double((a.y - v.y) * size.height)
        let bx = Double((b.x - v.x) * size.width), by = Double((b.y - v.y) * size.height)
        let la = hypot(ax, ay), lb = hypot(bx, by)
        guard la > 0, lb > 0 else { return 0 }
        let c = max(-1, min(1, (ax * bx + ay * by) / (la * lb)))
        return acos(c) * 180 / .pi
    }
}

// MARK: - View

struct PhotoMeasureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL

    @State private var session = PhotoSessionStore.shared
    @State private var tool: PhotoTool = .line
    @State private var dragOrigin: PhotoDoc?
    @State private var showExport = DebugLaunch.is("export")
    @State private var editingReference = false
    @State private var referenceText = ""
    @State private var editingText: UUID?
    @State private var textDraft = ""
    @State private var toast: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraDenied = false

    private var doc: PhotoDoc { session.doc }

    var body: some View {
        ZStack(alignment: .bottom) {
            editor
                .allowsHitTesting(!showExport)

            if showExport {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(PM.Motion.normal) { showExport = false } }
                    .accessibilityLabel("Close export")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
                PhotoExportSheet(
                    hasMeasurements: !measurementRows.isEmpty,
                    onClose: { withAnimation(PM.Motion.normal) { showExport = false } },
                    onSave: saveToProject,
                    render: { showTags, includeList in exportView(showTags: showTags, includeList: includeList) }
                )
                .transition(.move(edge: .bottom))
            }

            if let toast {
                ToastView(text: toast)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .onAppear {
            if DebugLaunch.isActive, !session.doc.hasPhoto {
                session.doc = .sample
                session.selected = session.doc.annotations.first?.id
            }
        }
        .alert("Known reference", isPresented: $editingReference) {
            TextField("Length in metres", text: $referenceText)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let v = PhotoFormat.parseMetres(referenceText) {
                    commit { $0.reference.metres = v }
                } else {
                    flash("Enter a length above 0 m")
                }
            }
        } message: {
            Text("Enter the real length of the lavender reference line, in metres. Other lengths are scaled from it.")
        }
        .alert("Text", isPresented: Binding(get: { editingText != nil }, set: { if !$0 { editingText = nil } })) {
            TextField("Label", text: $textDraft)
            Button("Cancel", role: .cancel) { editingText = nil }
            Button("Save") {
                if let id = editingText {
                    let t = String(textDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                    commit { d in
                        if let i = d.annotations.firstIndex(where: { $0.id == id }) { d.annotations[i].text = t.isEmpty ? "Text" : t }
                    }
                }
                editingText = nil
            }
        }
        .alert("Camera access is off", isPresented: $cameraDenied) {
            Button("Not now", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        } message: {
            Text("Allow camera access in Settings to take a photo, or choose one from your library.")
        }
        .fullScreenCover(isPresented: $showCamera) {
            PhotoCameraPicker { image in
                showCamera = false
                if let image { load(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickerItem = nil
                if let data, let image = UIImage(data: data) { load(image) } else { flash("That photo couldn't be opened") }
            }
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(spacing: 0) {
            HStack {
                IconCircleButton(icon: .back, label: "Back", iconSize: 18, stroke: 2) { dismiss() }
                Spacer()
                Button("Done") { withAnimation(PM.Motion.normal) { showExport = true } }
                    .font(.pm(15, .bold))
                    .foregroundStyle(PM.Colors.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Capsule().fill(PM.Colors.accent))
                    .buttonStyle(.pmPress)
                    .disabled(!doc.hasPhoto)
                    .opacity(doc.hasPhoto ? 1 : 0.5)
                    .accessibilityHint("Export or save the annotated photo")
            }
            .overlay {
                Text("Photo Measure").font(.pmNavTitle).foregroundStyle(PM.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56 - PM.Board.statusBar)

            // Board: photo at y 116, 370 tall; the 44 pt bar ends at y 100.
            Group {
                if doc.hasPhoto {
                    photo(interactive: true, showTags: true)
                } else {
                    emptyPhoto
                }
            }
            .padding(.top, 16)

            referenceCard
                .padding(.horizontal, 16)
                .padding(.top, 12)

            toolGrid
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .disabled(!doc.hasPhoto)
                .opacity(doc.hasPhoto ? 1 : 0.5)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                PhotoActionButton(title: "Undo", icon: "M9 14L4 9l5-5 M4 9h10a6 6 0 0 1 0 12h-3") { undo() }
                    .disabled(session.undo.isEmpty)
                PhotoActionButton(title: "Redo", icon: "M15 14l5-5-5-5 M20 9H10a6 6 0 0 0 0 12h3") { redo() }
                    .disabled(session.redo.isEmpty)
                PhotoActionButton(title: "Delete", icon: "M4 7h16 M9 7V4h6v3 M6 7l1 13h10l1-13") { deleteSelected() }
                    .disabled(doc.annotations.isEmpty)
                    .accessibilityHint("Deletes the selected annotation")
                PhotoActionButton(title: "Duplicate", icon: "M9 9h11v11H9z M5 15H4V4h11v1") { duplicate() }
                    .disabled(doc.annotations.isEmpty)
                    .accessibilityHint("Copies the selected annotation")
            }
            .padding(.horizontal, 16)
        }
    }

    /// No photo yet: choose one or take one.
    private var emptyPhoto: some View {
        VStack(spacing: 14) {
            PMIcon(.camera, size: 28, stroke: 1.7)
                .foregroundStyle(PM.Colors.accent)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PM.Colors.iconWell))
            Text("Measure on a photo").font(.pm(18, .bold)).foregroundStyle(PM.Colors.textPrimary)
            Text("Add a photo, mark something of known size, then draw lengths that are scaled from it.")
                .font(.pm(14))
                .foregroundStyle(PM.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .images) { Text("Choose photo") }
                    .buttonStyle(PMPrimaryButtonStyle(height: 48, fontSize: 15))
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photo") { openCamera() }
                        .buttonStyle(PMSecondaryButtonStyle(height: 48, fontSize: 15, fillWidth: true))
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(390 / 370, contentMode: .fit)
        .background(PM.Colors.surfaceSunken)
    }

    /// The photo with its annotations, fitted into the 390 × 370 board frame at the screen width.
    private func photo(interactive: Bool, showTags: Bool) -> some View {
        GeometryReader { g in
            let rect = fitRect(in: g.size)
            ZStack(alignment: .topLeading) {
                Color.black
                if doc.isSample {
                    HallwayScene().frame(width: g.size.width, height: g.size.height)
                } else if let image = doc.image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }

                referenceLayer(rect: rect, interactive: interactive)

                ForEach(doc.annotations) { ann in
                    annotationLayer(ann, rect: rect, interactive: interactive, showTags: showTags)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
        }
        .aspectRatio(390 / 370, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(photoSummary)
    }

    private var photoSummary: String {
        let ref = doc.reference.metres.map { "Reference \(PhotoFormat.metres($0))." } ?? "Reference not set."
        let items = measurementRows.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        return "Photo. \(ref) \(items)"
    }

    private func fitRect(in frame: CGSize) -> CGRect {
        if doc.isSample || doc.size.width <= 0 || doc.size.height <= 0 { return CGRect(origin: .zero, size: frame) }
        let s = min(frame.width / doc.size.width, frame.height / doc.size.height)
        let w = doc.size.width * s, h = doc.size.height * s
        return CGRect(x: (frame.width - w) / 2, y: (frame.height - h) / 2, width: w, height: h)
    }

    private func toView(_ p: CGPoint, _ r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
    }

    // MARK: Layers

    @ViewBuilder private func referenceLayer(rect r: CGRect, interactive: Bool) -> some View {
        let lav = Color(hex: 0xA9B6FF)
        let a = toView(doc.reference.a, r), b = toView(doc.reference.b, r)
        let ang = atan2(b.y - a.y, b.x - a.x)
        let nx = -sin(ang) * 6.5, ny = cos(ang) * 6.5
        Path { p in p.move(to: a); p.addLine(to: b) }
            .stroke(lav, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
        Path { p in
            for e in [a, b] {
                p.move(to: CGPoint(x: e.x - nx, y: e.y - ny))
                p.addLine(to: CGPoint(x: e.x + nx, y: e.y + ny))
            }
        }
        .stroke(lav, lineWidth: 2)
        Text(doc.reference.metres.map { "\(PhotoFormat.metres($0)) · ref" } ?? "Set reference")
            .font(.pm(12, .semibold))
            .monospacedDigit()
            .foregroundStyle(Color(hex: 0xF1F4F3))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color(hex: 0x0B0D0F, opacity: 0.88)))
            .overlay(Capsule().strokeBorder(lav, lineWidth: 1))
            .fixedSize()
            .position(x: (a.x + b.x) / 2, y: min(a.y, b.y) - 20)
            .onTapGesture { if interactive { beginReferenceEdit() } }
        if interactive {
            ForEach(0..<2, id: \.self) { i in
                Color.clear
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .position(i == 0 ? a : b)
                    .gesture(referenceDrag(index: i, rect: r))
                    .accessibilityElement()
                    .accessibilityLabel("Reference end \(i == 0 ? "1" : "2")")
                    .accessibilityHint("Drag to the ends of something you know the size of")
            }
        }
    }

    @ViewBuilder private func annotationLayer(_ ann: PhotoAnnotation, rect r: CGRect, interactive: Bool, showTags: Bool) -> some View {
        let pts = ann.points.map { toView($0, r) }
        let mint = Color(hex: 0x52F2B8)
        let selected = ann.id == session.selected && interactive

        switch ann.kind {
        case .line, .arrow:
            if pts.count == 2 {
                Path { p in p.move(to: pts[0]); p.addLine(to: pts[1]) }
                    .stroke(Color(hex: 0x03140D, opacity: 0.35), lineWidth: 4)
                Path { p in
                    p.move(to: pts[0]); p.addLine(to: pts[1])
                    if ann.kind == .arrow {
                        let ang = atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x)
                        for d in [-0.5, 0.5] {
                            p.move(to: pts[1])
                            p.addLine(to: CGPoint(x: pts[1].x - cos(ang + d) * 14, y: pts[1].y - sin(ang + d) * 14))
                        }
                    }
                }
                .stroke(mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .shadow(color: mint.opacity(0.6), radius: 4)
            }
        case .rectangle:
            if pts.count == 2 {
                Path(CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y),
                            width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y)))
                    .stroke(mint, lineWidth: 2)
                    .shadow(color: mint.opacity(0.6), radius: 4)
            }
        case .circle:
            if pts.count == 2 {
                let rad = hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y)
                Path(ellipseIn: CGRect(x: pts[0].x - rad, y: pts[0].y - rad, width: rad * 2, height: rad * 2))
                    .stroke(mint, lineWidth: 2)
                    .shadow(color: mint.opacity(0.6), radius: 4)
            }
        case .angle:
            if pts.count == 3 {
                Path { p in p.move(to: pts[0]); p.addLine(to: pts[1]); p.addLine(to: pts[2]) }
                    .stroke(mint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .shadow(color: mint.opacity(0.6), radius: 4)
            }
        case .text:
            EmptyView()
        }

        if let label = label(for: ann), let anchor = labelAnchor(ann, pts) {
            PhotoLabel(value: label.0, tag: showTags ? label.1 : nil, accent: selected || ann.kind != .text)
                .position(anchor)
                .gesture(interactive ? moveDrag(ann.id, rect: r) : nil)
                .simultaneousGesture(TapGesture().onEnded {
                    guard interactive else { return }
                    session.selected = ann.id
                    tool = ann.kind
                    if ann.kind == .text { textDraft = ann.text; editingText = ann.id }
                })
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(ann.kind.rawValue), \(label.0)")
                .accessibilityHint(interactive ? "Drag to move" : "")
        }

        if ann.kind != .text {
            ForEach(pts.indices, id: \.self) { i in
                PhotoHandle(label: ann.kind == .line ? (i == 0 ? "A" : "B") : nil, selected: selected)
                    .position(pts[i])
                    .gesture(interactive ? handleDrag(ann.id, index: i, rect: r) : nil)
                    .accessibilityLabel("\(ann.kind.rawValue) point \(i + 1)")
                    .accessibilityHidden(!interactive)
            }
        }
    }

    /// (value, source tag) for an annotation's chip.
    private func label(for ann: PhotoAnnotation) -> (String, String?)? {
        let mpu = doc.metresPerUnit
        switch ann.kind {
        case .line:
            guard ann.points.count == 2 else { return nil }
            guard let mpu else { return ("Set reference", nil) }
            return (PhotoFormat.metres(doc.units(ann.points[0], ann.points[1]) * mpu), "CALCULATED")
        case .rectangle:
            guard ann.points.count == 2, let mpu else { return ann.points.count == 2 ? ("Set reference", nil) : nil }
            let w = Double(abs(ann.points[1].x - ann.points[0].x) * doc.size.width) * mpu
            let h = Double(abs(ann.points[1].y - ann.points[0].y) * doc.size.height) * mpu
            return (String(format: "%.2f × %.2f m", w, h), "CALCULATED")
        case .circle:
            guard ann.points.count == 2 else { return nil }
            guard let mpu else { return ("Set reference", nil) }
            return ("⌀ " + PhotoFormat.metres(2 * doc.units(ann.points[0], ann.points[1]) * mpu), "CALCULATED")
        case .angle:
            guard ann.points.count == 3 else { return nil }
            let a = PhotoFormat.angle(ann.points[0], ann.points[1], ann.points[2], size: doc.size)
            return (String(format: "%.1f°", a), "CALCULATED")
        case .text:
            return (ann.text.isEmpty ? "Text" : ann.text, nil)
        case .arrow:
            return nil
        }
    }

    private func labelAnchor(_ ann: PhotoAnnotation, _ pts: [CGPoint]) -> CGPoint? {
        switch ann.kind {
        case .line, .rectangle:
            guard pts.count == 2 else { return nil }
            return CGPoint(x: (pts[0].x + pts[1].x) / 2 + 1.5, y: min(pts[0].y, pts[1].y) - 31)
        case .circle:
            guard pts.count == 2 else { return nil }
            let rad = hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y)
            return CGPoint(x: pts[0].x, y: pts[0].y - rad - 20)
        case .angle:
            guard pts.count == 3 else { return nil }
            return CGPoint(x: pts[1].x, y: pts[1].y + 28)
        case .text:
            return pts.first
        case .arrow:
            return nil
        }
    }

    /// Rows for the PDF list and saving: (name, value).
    private var measurementRows: [(String, String)] {
        var counts: [PhotoTool: Int] = [:]
        return doc.annotations.compactMap { ann -> (String, String)? in
            guard ann.kind != .text, ann.kind != .arrow, let l = label(for: ann), l.1 != nil else { return nil }
            counts[ann.kind, default: 0] += 1
            let n = counts[ann.kind]!
            let name: String = doc.isSample && ann.kind == .line && n == 1 ? "Hallway wall" : "\(ann.kind.rawValue) \(n)"
            return (name, l.0)
        }
    }

    // MARK: Gestures

    private func clampNorm(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0.01), 0.99), y: min(max(p.y, 0.01), 0.99))
    }

    private func delta(_ t: CGSize, _ r: CGRect) -> CGPoint {
        guard r.width > 0, r.height > 0 else { return .zero }
        return CGPoint(x: t.width / r.width, y: t.height / r.height)
    }

    private func handleDrag(_ id: UUID, index: Int, rect r: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                if dragOrigin == nil { dragOrigin = session.doc; session.selected = id }
                guard let o = dragOrigin, let i = o.annotations.firstIndex(where: { $0.id == id }),
                      index < o.annotations[i].points.count else { return }
                let d = delta(v.translation, r)
                let s = o.annotations[i].points[index]
                session.doc.annotations[i].points[index] = clampNorm(CGPoint(x: s.x + d.x, y: s.y + d.y))
            }
            .onEnded { _ in endDrag() }
    }

    private func moveDrag(_ id: UUID, rect r: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                if dragOrigin == nil { dragOrigin = session.doc; session.selected = id }
                guard let o = dragOrigin, let i = o.annotations.firstIndex(where: { $0.id == id }) else { return }
                let d = delta(v.translation, r)
                session.doc.annotations[i].points = o.annotations[i].points.map {
                    clampNorm(CGPoint(x: $0.x + d.x, y: $0.y + d.y))
                }
            }
            .onEnded { _ in endDrag() }
    }

    private func referenceDrag(index: Int, rect r: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                if dragOrigin == nil { dragOrigin = session.doc }
                guard let o = dragOrigin else { return }
                let d = delta(v.translation, r)
                let s = index == 0 ? o.reference.a : o.reference.b
                let p = clampNorm(CGPoint(x: s.x + d.x, y: s.y + d.y))
                if index == 0 { session.doc.reference.a = p } else { session.doc.reference.b = p }
            }
            .onEnded { _ in endDrag() }
    }

    private func endDrag() {
        if let o = dragOrigin, o != session.doc {
            session.undo.append(o)
            session.redo.removeAll()
            Haptics.selection()
        }
        dragOrigin = nil
    }

    // MARK: Cards

    private var referenceCard: some View {
        let set = doc.reference.metres != nil
        let name = doc.reference.name.flatMap { $0.isEmpty ? nil : $0 }
        return HStack(spacing: 12) {
            PMIcon(.ruler, size: 18, stroke: 1.8)
                .foregroundStyle(Color(hex: 0xA9B6FF))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(dark: 0x1E2330, light: 0xE9ECFB)))
            VStack(alignment: .leading, spacing: 2) {
                if let metres = doc.reference.metres {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name.map { "Reference · \($0)" } ?? "Reference")
                            .font(.pm(13, .semibold))
                            .foregroundStyle(PM.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(PhotoFormat.metres(metres))
                            .font(.pm(16, .bold))
                            .monospacedDigit()
                            .foregroundStyle(PM.Colors.textPrimary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    Text("Other lengths scale from it")
                        .font(.pm(12))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("Set a known reference")
                        .font(.pm(14, .semibold))
                        .foregroundStyle(PM.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Drag the lavender line across something you know, then enter its length")
                        .font(.pm(12))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(set ? "Known reference, user-entered: \(name.map { "\($0), " } ?? "")\(PhotoFormat.metres(doc.reference.metres ?? 0)). Other lengths are scaled from it."
                                    : "Set a known reference")
            Button(set ? "Edit" : "Set") { beginReferenceEdit() }
                .buttonStyle(PMSecondaryButtonStyle(height: 44, fontSize: 13, horizontalPadding: 12))
                .disabled(!doc.hasPhoto)
                .accessibilityLabel(set ? "Edit reference length" : "Set reference length")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .pmCard(radius: 20)
        .accessibilityElement(children: .contain)
    }

    private var toolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(PhotoTool.allCases, id: \.self) { t in
                let on = t == tool
                Button {
                    Haptics.selection()
                    add(t)
                } label: {
                    HStack(spacing: 8) {
                        SVGStroke(d: t.icon, size: 20, lineWidth: 1.7)
                        Text(t.rawValue).font(.pm(12, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? PM.Colors.accent : PM.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(on ? Color(dark: 0x122420, light: 0xE6F2EC) : PM.Colors.surface))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(on ? PM.Colors.accent : PM.Colors.border, lineWidth: on ? 1.5 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.pmPress)
                .accessibilityLabel("Add \(t.rawValue.lowercased())")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: Export

    private func exportView(showTags: Bool, includeList: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            photo(interactive: false, showTags: showTags)
                .frame(width: 390, height: 370)
            if includeList && !measurementRows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MEASUREMENTS").font(.pm(11, .bold)).tracking(1).foregroundStyle(Color(hex: 0x4F585E))
                    if let m = doc.reference.metres {
                        row("Reference", PhotoFormat.metres(m), showTags ? "User-entered" : nil)
                    }
                    ForEach(measurementRows.indices, id: \.self) { i in
                        row(measurementRows[i].0, measurementRows[i].1, showTags ? "Calculated" : nil)
                    }
                    Text("Scaled from the reference. Only accurate in the reference's plane.")
                        .font(.pm(10)).foregroundStyle(Color(hex: 0x4F585E))
                        .padding(.top, 4)
                }
                .padding(16)
                .frame(width: 390, alignment: .leading)
                .background(Color.white)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func row(_ name: String, _ value: String, _ tag: String?) -> some View {
        HStack {
            Text(name).font(.pm(13)).foregroundStyle(Color(hex: 0x0E1113))
            Spacer()
            if let tag { Text(tag).font(.pm(10, .semibold)).foregroundStyle(Color(hex: 0x4F585E)) }
            Text(value).font(.pm(13, .semibold)).monospacedDigit().foregroundStyle(Color(hex: 0x0E1113))
        }
    }

    // MARK: Actions

    private func commit(_ change: (inout PhotoDoc) -> Void) {
        let before = session.doc
        change(&session.doc)
        if before != session.doc {
            session.undo.append(before)
            session.redo.removeAll()
        }
    }

    private func flash(_ text: String) {
        withAnimation(PM.Motion.normal) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(PM.Motion.normal) { toast = nil }
        }
    }

    private func beginReferenceEdit() {
        referenceText = doc.reference.metres.map { String(format: "%.2f", $0) } ?? ""
        editingReference = true
    }

    private func load(_ raw: UIImage) {
        // Normalise orientation and cap the size so huge photos don't exhaust memory.
        let maxSide: CGFloat = 2048
        let px = CGSize(width: raw.size.width * raw.scale, height: raw.size.height * raw.scale)
        guard px.width > 0, px.height > 0 else { flash("That photo couldn't be opened"); return }
        let k = min(1, maxSide / max(px.width, px.height))
        let target = CGSize(width: (px.width * k).rounded(), height: (px.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            raw.draw(in: CGRect(origin: .zero, size: target))
        }
        withAnimation(PM.Motion.normal) {
            session.doc = PhotoDoc(image: image, isSample: false, size: target)
            session.undo.removeAll()
            session.redo.removeAll()
            session.selected = nil
        }
    }

    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showCamera = true
        case .notDetermined:
            Task {
                let ok = await AVCaptureDevice.requestAccess(for: .video)
                if ok { showCamera = true } else { cameraDenied = true }
            }
        default: cameraDenied = true
        }
    }

    /// Adds a new annotation of the tool's kind near the middle of the photo, staggered so they don't stack.
    private func add(_ t: PhotoTool) {
        tool = t
        guard doc.hasPhoto else { return }
        let k = CGFloat(doc.annotations.count % 5) * 0.06
        let cx = 0.5, cy = 0.55 - 0.12 + k
        let pts: [CGPoint]
        switch t {
        case .line, .arrow: pts = [CGPoint(x: cx - 0.22, y: cy), CGPoint(x: cx + 0.22, y: cy)]
        case .rectangle: pts = [CGPoint(x: cx - 0.18, y: cy - 0.12), CGPoint(x: cx + 0.18, y: cy + 0.12)]
        case .circle: pts = [CGPoint(x: cx, y: cy), CGPoint(x: cx + 0.12, y: cy)]
        case .angle: pts = [CGPoint(x: cx + 0.2, y: cy - 0.15), CGPoint(x: cx - 0.15, y: cy + 0.1), CGPoint(x: cx + 0.25, y: cy + 0.1)]
        case .text: pts = [CGPoint(x: cx, y: cy)]
        }
        let ann = PhotoAnnotation(kind: t, points: pts.map(clampNorm), text: t == .text ? "Text" : "")
        commit { $0.annotations.append(ann) }
        session.selected = ann.id
        if t == .text { textDraft = ""; editingText = ann.id }
    }

    private var selectedIndex: Int? {
        if let id = session.selected, let i = doc.annotations.firstIndex(where: { $0.id == id }) { return i }
        return doc.annotations.indices.last
    }

    private func undo() {
        guard let last = session.undo.popLast() else { return }
        session.redo.append(session.doc)
        withAnimation(PM.Motion.normal) { session.doc = last }
    }

    private func redo() {
        guard let next = session.redo.popLast() else { return }
        session.undo.append(session.doc)
        withAnimation(PM.Motion.normal) { session.doc = next }
    }

    private func deleteSelected() {
        guard let i = selectedIndex else { return }
        withAnimation(PM.Motion.normal) { commit { $0.annotations.remove(at: i) } }
        session.selected = doc.annotations.last?.id
    }

    private func duplicate() {
        guard let i = selectedIndex else { return }
        var copy = doc.annotations[i]
        copy.id = UUID()
        copy.points = copy.points.map { clampNorm(CGPoint(x: $0.x + 0.04, y: $0.y - 0.1)) }
        withAnimation(PM.Motion.normal) { commit { $0.annotations.append(copy) } }
        session.selected = copy.id
    }

    private func saveToProject() {
        let rows = measurementRows
        guard !rows.isEmpty else {
            flash(doc.metresPerUnit == nil ? "Set the reference length first" : "Add a measurement first")
            return
        }
        let store = MeasurementStore.shared
        let project = store.projects.first { $0.name == "Kitchen Renovation" && doc.isSample } ?? store.projects.first
        let now = Date()
        for r in rows {
            store.add(MeasurementRecord(name: r.0, value: r.1, source: .calculated,
                                        tool: .photo, projectID: project?.id, date: now))
        }
        withAnimation(PM.Motion.normal) {
            showExport = false
            toast = "Saved to \(project?.name ?? "History")"
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(PM.Motion.normal) { toast = nil }
            router.select(project != nil ? .projects : .history)
        }
    }
}

// MARK: - Pieces

/// Measurement chip over the photo: value plus an optional source tag.
private struct PhotoLabel: View {
    var value: String
    var tag: String?
    var accent: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(value).font(.pm(16, .medium)).monospacedDigit()
                .foregroundStyle(Color(hex: 0xF1F4F3))
            if let tag {
                Text(tag).font(.pm(12, .bold)).foregroundStyle(Color(hex: 0xA7B0B5))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(Color(hex: 0x0B0D0F, opacity: 0.9)))
        .overlay(Capsule().strokeBorder(accent ? Color(hex: 0x52F2B8) : Color(hex: 0x2A3238), lineWidth: 1))
        .fixedSize()
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Endpoint handle: 24 pt mint circle with a letter, or a plain 16 pt dot.
private struct PhotoHandle: View {
    var label: String?
    var selected: Bool

    var body: some View {
        Group {
            if let label {
                Text(label)
                    .font(.pm(12, .heavy))
                    .foregroundStyle(Color(hex: 0x03140D))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(hex: 0x52F2B8)))
            } else {
                Circle().fill(Color(hex: 0x52F2B8))
                    .overlay(Circle().strokeBorder(Color(hex: 0x03140D), lineWidth: 2))
                    .frame(width: selected ? 18 : 14, height: selected ? 18 : 14)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
}

private struct PhotoActionButton: View {
    var title: String
    var icon: String
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            // Icon above a small label so all four fit at equal widths on a 402 pt screen.
            VStack(spacing: 4) {
                SVGStroke(d: icon, size: 18, lineWidth: 1.8)
                Text(title).font(.pm(11, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(PM.Colors.textPrimary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PM.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pmPress)
        .accessibilityLabel(title)
    }
}

/// System camera for "Take photo".
private struct PhotoCameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

/// Export sheet: format radio cards, two switches, an accuracy note, Save to project and Share.
private struct PhotoExportSheet<Snapshot: View>: View {
    var hasMeasurements: Bool
    var onClose: () -> Void
    var onSave: () -> Void
    var render: (_ showTags: Bool, _ includeList: Bool) -> Snapshot

    @State private var format: ExportFormat = .pdf
    @State private var includeList = true
    @State private var showTags = true
    @State private var shareURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(PM.Colors.tickMinor).frame(width: 40, height: 5).frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            HStack {
                Text("Export").font(.pm(22, .bold)).foregroundStyle(PM.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconCircleButton(icon: .close, label: "Close", iconSize: 16, stroke: 2,
                                 fill: PM.Colors.surfaceRaised, border: .clear, action: onClose)
            }
            HStack(spacing: 10) {
                formatCard(.png, title: "PNG", subtitle: "Image with annotations")
                formatCard(.pdf, title: "PDF", subtitle: "Report with measurement list")
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                switchRow("Include measurement list", isOn: $includeList)
                PM.Colors.borderStrong.frame(height: 1)
                switchRow("Show source tags", isOn: $showTags)
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(PM.Colors.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
            Text("Photo measurements are scaled from the reference you entered. They are only as accurate as that reference.")
                .font(.pm(13))
                .lineSpacing(13 * 0.4 - 2.3)
                .foregroundStyle(PM.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Save to project", action: onSave)
                    .buttonStyle(PMSecondaryButtonStyle(height: 56, fontSize: 16, fillWidth: true))
                Group {
                    if let shareURL {
                        ShareLink(item: shareURL) { Text("Share") }
                    } else {
                        Button("Share") { renderShare() }
                    }
                }
                .buttonStyle(PMPrimaryButtonStyle(height: 56, fontSize: 16))
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 20)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(PM.Colors.surface)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                        .stroke(PM.Colors.border, lineWidth: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .onAppear(perform: renderShare)
        .onChange(of: format) { renderShare() }
        .onChange(of: includeList) { renderShare() }
        .onChange(of: showTags) { renderShare() }
        .accessibilityAddTraits(.isModal)
    }

    private func formatCard(_ f: ExportFormat, title: String, subtitle: String) -> some View {
        let on = f == format
        return Button {
            Haptics.selection()
            format = f
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if on { PMIcon(.check, size: 14, stroke: 3).foregroundStyle(PM.Colors.accent) }
                    Text(title).font(.pm(16, .bold))
                }
                Text(subtitle).font(.pm(12)).foregroundStyle(PM.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(PM.Colors.textPrimary)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(on ? Color(dark: 0x122420, light: 0xE6F2EC) : PM.Colors.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(on ? PM.Colors.accent : PM.Colors.borderStrong, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.pmPress)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.pm(15)).foregroundStyle(PM.Colors.textPrimary)
            Spacer()
            PhotoSwitch(isOn: isOn)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
        .accessibilityAction { isOn.wrappedValue.toggle() }
    }

    /// Writes the annotated photo as PNG, or a one-page PDF with the list, to a temporary file.
    private func renderShare() {
        let renderer = ImageRenderer(content: render(showTags, includeList && format == .pdf))
        renderer.scale = 3
        let dir = FileManager.default.temporaryDirectory
        switch format {
        case .png:
            guard let image = renderer.uiImage, let data = image.pngData() else { shareURL = nil; return }
            let url = dir.appendingPathComponent("Plumb photo measure.png")
            do { try data.write(to: url, options: .atomic); shareURL = url } catch { shareURL = nil }
        case .pdf:
            let url = dir.appendingPathComponent("Plumb photo measure.pdf")
            var ok = false
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
                ctx.closePDF()
                ok = true
            }
            shareURL = ok ? url : nil
        }
    }
}

/// 52 × 32 switch: mint track with a dark 26 pt knob when on.
private struct PhotoSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? PM.Colors.accent : PM.Colors.borderStrong)
                Circle().fill(isOn ? PM.Colors.onAccent : PM.Colors.textSecondary)
                    .frame(width: 26, height: 26)
                    .padding(3)
            }
            .frame(width: 52, height: 32)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PhotoMeasureView().environment(Router())
}
