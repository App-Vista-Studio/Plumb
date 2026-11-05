//
//  ARMeasureView.swift
//  Plumb
//
//  AR Measure sequence (board 13): tracking → ready → measuring → end point placed → saved.
//  The kitchen scene stands in for the camera feed; taps advance the flow as the board shows.
//

import SwiftUI

enum ARTrackingQuality {
    case starting, good, limited

    var label: String {
        switch self {
        case .starting: "Tracking: Starting"
        case .good: "Tracking: Good"
        case .limited: "Tracking: Limited"
        }
    }

    var color: Color {
        switch self {
        case .starting: Color(hex: 0xA9B6FF)
        case .good: Color(hex: 0x52F2B8)
        case .limited: Color(hex: 0xFFB547)
        }
    }
}

/// Tracking pill over the camera: 30 tall, 12 bold, tracking 0.4, icon + word + colour.
struct ARTrackingBadge: View {
    var quality: ARTrackingQuality

    var body: some View {
        HStack(spacing: 6) {
            switch quality {
            case .good: PMIcon(.check, size: 13, stroke: 2.6)
            case .starting: PMIcon(.rotate, size: 13, stroke: 2.2)
            case .limited: PMIcon(.warning, size: 13, stroke: 2.4)
            }
            Text(quality.label)
        }
        .font(.pm(12, .bold))
        .tracking(0.4)
        .foregroundStyle(quality.color)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(ARChrome.glassStrong))
        .accessibilityElement(children: .combine)
    }
}

/// Fixed dark glass for chrome drawn over the camera feed. It stays dark in light mode, like the camera.
enum ARChrome {
    static let glass = Color(hex: 0x0B0D0F, opacity: 0.72)
    static let glassStrong = Color(hex: 0x0B0D0F, opacity: 0.78)
    static let cameraBase = Color(hex: 0x1A1F22)
    static let text = Color(hex: 0xF1F4F3)
    static let textSecondary = Color(hex: 0xA7B0B5)
    static let line = Color(hex: 0x2A3238)
    static let mint = Color(hex: 0x52F2B8)
}

/// Round glass button over the camera (close, info).
struct ARGlassButton: View {
    var icon: PMIconName
    var label: String
    var stroke: CGFloat = 2
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PMIcon(icon, size: 18, stroke: stroke)
                .foregroundStyle(ARChrome.text)
                .frame(width: 44, height: 44)
                .background(Circle().fill(ARChrome.glass))
                .contentShape(Circle())
        }
        .buttonStyle(.pmPress)
        .accessibilityLabel(label)
    }
}

/// Glass title pill: 36 tall, 15 semibold.
struct ARTitlePill: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.pm(15, .semibold))
            .foregroundStyle(ARChrome.text)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(ARChrome.glass))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Secondary pill over the camera: glass fill, 1 pt line border.
struct ARGlassPillStyle: ButtonStyle {
    var height: CGFloat = 56
    var fontSize: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(fontSize, .semibold))
            .foregroundStyle(ARChrome.text)
            .padding(.horizontal, 20)
            .frame(height: height)
            .background(Capsule().fill(ARChrome.glassStrong))
            .overlay(Capsule().strokeBorder(ARChrome.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

private enum ARStep: Int { case scanning, ready, measuring, done, saved }

private enum ARUnit: String, CaseIterable {
    case cm, m, `in`, ft

    /// Honest precision: AR is good to 1 cm, so no unit shows finer than that.
    func format(metres: Double) -> String {
        guard metres.isFinite, metres >= 0 else { return "—" }
        switch self {
        case .cm: return String(format: "%.0f cm", metres * 100)
        case .m: return String(format: "%.2f m", metres)
        case .in: return String(format: "%.0f in", metres / 0.0254)
        case .ft: return String(format: "%.1f ft", metres / 0.3048)
        }
    }
}

/// Debug-only stand-in for the camera so each board phone can be captured in the Simulator.
private struct ARFixture {
    var step: ARStep

    static func fromLaunch() -> ARFixture? {
        #if DEBUG
        guard DebugLaunch.isActive, !ARMeasureSession.isSupported else { return nil }
        let step: ARStep = switch DebugLaunch.state {
        case "ready": .ready
        case "measuring": .measuring
        case "done": .done
        case "saved": .saved
        default: .scanning
        }
        return ARFixture(step: step)
        #else
        return nil
        #endif
    }
}

struct ARMeasureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var session = ARMeasureSession()
    @State private var fixture = ARFixture.fromLaunch()
    @State private var unit: ARUnit = AppSettings.shared.units == .imperial ? .ft : .m
    @State private var saved: SavedSummary?
    @State private var showToast = false
    @State private var showInfo = false
    /// "+" was tapped after a finished segment: show Start point again, keeping what's measured.
    @State private var pendingAdd = false

    private struct SavedSummary: Equatable {
        var projectName: String?
        var projectID: UUID?
        var name: String
        var metres: Double
    }

    private var store: MeasurementStore { MeasurementStore.shared }
    private var targetProject: Project? {
        store.projects.first { $0.name == "Kitchen Renovation" && fixture != nil } ?? store.projects.first
    }

    // MARK: Derived state

    private var step: ARStep {
        if saved != nil { return .saved }
        if let fixture { return fixture.step }
        if session.openSegment != nil { return .measuring }
        if let last = session.segments.last, last.b != nil, !last.saved, !pendingAdd { return .done }
        if session.segments.isEmpty, session.tracking != .good || !session.hasSurface { return .scanning }
        return .ready
    }

    private var tracking: ARTrackingQuality {
        guard fixture == nil else { return step == .scanning ? .starting : .good }
        return session.tracking
    }

    private var canPlace: Bool { fixture != nil || session.canPlace }

    /// Board values for the fixture: a 2.43 m counter, 1.23 m while measuring.
    private var fixtureFinal: Double { 2.43 }

    var body: some View {
        ZStack {
            cameraLayer
            chromeLayer
        }
        .background(ARChrome.cameraBase.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            if fixture == nil { session.start() }
            if fixture?.step == .saved {
                // Board phone 5: saved to the sample project, toast showing.
                let p = targetProject
                saved = SavedSummary(projectName: p?.name, projectID: p?.id, name: "Counter length", metres: fixtureFinal)
                showToast = true
            }
        }
        .onDisappear { session.pause() }
        .onChange(of: scenePhase) { _, phase in
            guard fixture == nil else { return }
            if phase == .active { session.start() } else if phase == .background { session.pause() }
        }
        .onChange(of: session.availability) { _, a in handle(a) }
    }

    private func handle(_ a: ARMeasureSession.Availability) {
        switch a {
        case .unsupported: replaceRoute(with: .unavailable(.arUnsupported))
        case .cameraDenied: replaceRoute(with: .unavailable(.cameraPermission))
        default: break
        }
    }

    private func replaceRoute(with route: Route) {
        if let i = router.path.lastIndex(of: .ar) { router.path[i] = route } else { router.push(route) }
    }

    // MARK: Camera layer (full screen)

    private var cameraLayer: some View {
        GeometryReader { g in
            let s = g.size.width / PM.Board.width
            ZStack(alignment: .topLeading) {
                if fixture != nil {
                    fixtureBackdrop(g: g, s: s)
                } else {
                    ARCameraView(session: session)
                    CameraVignette(bottomHeight: 290).allowsHitTesting(false)
                }

                overlay(s: s, size: g.size)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { advanceByTap() }
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private func fixtureBackdrop(g: GeometryProxy, s: CGFloat) -> some View {
        KitchenScene().sceneBox(0, -40 * s, 390 * s, 600 * s)
        KitchenFloorScene().sceneBox(0, 560 * s, 390 * s, max(g.size.height - 560 * s, 284 * s))
        CameraVignette(bottomHeight: 290)
        if step == .scanning {
            ARScanGrid().sceneBox(0, 140 * s, g.size.width, max(g.size.height - 140 * s, 0))
            ARParticles(scale: s, animate: !reduceMotion)
                .transition(.opacity)
        } else {
            ARPlaneHighlight().sceneBox(0, 278 * s, g.size.width, 30 * s)
                .transition(.opacity)
        }
    }

    /// Reticle, segments, points and distance labels, in view coordinates.
    @ViewBuilder private func overlay(s: CGFloat, size: CGSize) -> some View {
        let segs = screenSegments(s: s)
        let reticle = reticlePoint(s: s)
        let lastDone = segs.last { $0.complete }

        if let reticle, step == .ready || step == .measuring {
            ARReticle().position(reticle)
        }

        ForEach(segs) { seg in
            if let a = seg.a, let b = seg.b {
                ARMeasureLine(from: a, to: b)
            }
            if let a = seg.a {
                if !seg.complete || seg.id == segs.first?.id { ARHalo(animate: !reduceMotion).position(a) }
                ARPoint().position(a)
            }
            if seg.complete, let b = seg.b { ARPoint().position(b) }

            // Earlier finished segments keep a compact label at their midpoint.
            if seg.complete, seg.id != lastDone?.id, let a = seg.a, let b = seg.b, let m = seg.metres {
                ARDistanceChip(text: unit.format(metres: m))
                    .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + 26 * s)
            }
        }

        if step == .measuring, let open = segs.last, !open.complete, let m = open.metres, let r = reticle {
            ARDistanceChip(text: unit.format(metres: m))
                .position(x: r.x, y: r.y + (16 + 17) * s)
        }

        if step == .done || step == .saved, let seg = lastDone, let a = seg.a, let b = seg.b, let m = seg.metres {
            ARFinalCard(value: unit.format(metres: m))
                .position(x: fixture != nil ? 195 * s : (a.x + b.x) / 2,
                          y: fixture != nil ? (330 + 34) * s : max(a.y, b.y) + 56)
        }
    }

    private func screenSegments(s: CGFloat) -> [ARScreenSegment] {
        guard fixture != nil else { return session.screenSegments }
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let a = CGPoint(x: 30 * s, y: 308 * s)
        switch step {
        case .measuring:
            return [ARScreenSegment(id: id, a: a, b: CGPoint(x: 197 * s, y: 308 * s), metres: 1.23, complete: false)]
        case .done, .saved:
            return [ARScreenSegment(id: id, a: a, b: CGPoint(x: 360 * s, y: 308 * s), metres: fixtureFinal, complete: true)]
        default:
            return []
        }
    }

    private func reticlePoint(s: CGFloat) -> CGPoint? {
        guard fixture != nil else { return session.reticle }
        switch step {
        case .ready: return CGPoint(x: 195 * s, y: 293 * s)
        case .measuring: return CGPoint(x: 197 * s, y: 308 * s)
        default: return nil
        }
    }

    // MARK: Chrome layer (inside the safe area)

    private var chromeLayer: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                HStack {
                    ARGlassButton(icon: .close, label: "Close AR Measure") { dismiss() }
                    Spacer()
                    ARTitlePill(title: "AR Measure")
                    Spacer()
                    ARGlassButton(icon: .info, label: "Measurement info", stroke: 1.8) {
                        withAnimation(PM.Motion.normal) { showInfo.toggle() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56 - PM.Board.statusBar)

                // Board: badge at y 110, the 44 pt bar ends at y 100.
                ARTrackingBadge(quality: tracking)
                    .padding(.top, 10)
                    .animation(PM.Motion.normal, value: tracking)

                // Board: hint pills at y 196, toast at y 160; the badge ends at y 140.
                ZStack(alignment: .top) {
                    hintPill
                    if showToast {
                        HStack(spacing: 10) {
                            PMIcon(.check, size: 18, stroke: 2.6)
                            Text("MEASUREMENT SAVED")
                            Spacer(minLength: 0)
                        }
                        .font(.pm(15, .bold))
                        .foregroundStyle(PM.Colors.onAccent)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Capsule().fill(PM.Colors.accent))
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                    if showInfo {
                        ARInfoPanel(rows: infoRows, good: tracking == .good)
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)

                Spacer(minLength: 0)

                if case .failed(let message) = session.availability, fixture == nil {
                    ARFailureCard(message: message) { session.restart() }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                bottomControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, g.safeAreaInsets.bottom > 0 ? 0 : 20)
                    .background(alignment: .bottom) { ARBottomScrim() }
            }
        }
    }

    @ViewBuilder private var hintPill: some View {
        if fixture == nil, tracking != .good, let text = session.coaching, step != .saved {
            ARHintPill(spacing: 10) {
                PMIcon(tracking == .starting ? .phoneSides : .warning, size: 18, stroke: 1.8)
                    .foregroundStyle(tracking == .starting ? ARChrome.text : Color(hex: 0xFFB547))
                Text(text)
            }
            .padding(.top, 56)
            .transition(.opacity)
        } else if step == .scanning {
            ARHintPill {
                PMIcon(.phoneSides, size: 18, stroke: 1.8)
                Text("Move your \(Device.name) slowly")
            }
            .padding(.top, 56)
            .transition(.opacity)
        } else if step == .ready, reticlePoint(s: 1) != nil {
            ARHintPill(spacing: 8) {
                PMIcon(.check, size: 16, stroke: 2.4).foregroundStyle(ARChrome.mint)
                Text("Ready · Surface detected")
            }
            .padding(.top, 56)
            .transition(.opacity)
        } else if step == .ready || step == .measuring, fixture == nil, session.reticle == nil {
            ARHintPill(spacing: 8) {
                PMIcon(.phoneSides, size: 18, stroke: 1.8)
                Text("Aim the dot at a surface")
            }
            .padding(.top, 56)
            .transition(.opacity)
        }
    }

    private var infoRows: [(String, String)] {
        [("Source", "AR-derived"),
         ("Tracking", tracking.label.replacingOccurrences(of: "Tracking: ", with: "")),
         ("Surface", fixture != nil || session.reticle != nil ? "Detected" : "Searching"),
         ("Display precision", "1 cm")]
    }

    @ViewBuilder private var bottomControls: some View {
        VStack(spacing: 12) {
            if step == .measuring || step == .done {
                ZStack {
                    ARUnitPicker(unit: $unit)
                        .frame(maxWidth: .infinity)
                    HStack {
                        ARGlassButton(icon: .undo, label: "Undo last point", stroke: 1.8) { undo() }
                        Spacer()
                        if step == .done {
                            ARGlassButton(icon: .plus, label: "Measure another distance", stroke: 2) { addAnother() }
                        }
                    }
                }
            }
            switch step {
            case .scanning:
                Text(fixture == nil && session.availability == .checking ? "Starting the camera…" : "Point at the floor, a wall or a table.")
                    .font(.pm(14, .medium))
                    .foregroundStyle(ARChrome.text.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .frame(maxWidth: .infinity)
                Text("Start point")
                    .font(.pm(17, .bold))
                    .foregroundStyle(ARChrome.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Capsule().fill(ARChrome.glassStrong))
                    .overlay(Capsule().strokeBorder(ARChrome.line, lineWidth: 1))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Available once a surface is detected")
            case .ready:
                Button { place() } label: {
                    HStack(spacing: 10) {
                        PMIcon(.plus, size: 18, stroke: 2.2)
                        Text("Start point")
                    }
                }
                .buttonStyle(ARPlaceButtonStyle(enabled: canPlace))
                .disabled(!canPlace)
            case .measuring:
                Button("End point") { place() }
                    .buttonStyle(ARPlaceButtonStyle(enabled: canPlace))
                    .disabled(!canPlace)
            case .done:
                HStack(spacing: 10) {
                    Button("Save") { save() }
                        .buttonStyle(PMPrimaryButtonStyle(height: 56, fontSize: 16))
                    Button("Photo") { router.push(.photo) }
                        .buttonStyle(ARGlassPillStyle())
                        .accessibilityHint("Opens Photo Measure")
                    Button("Reset") { reset() }
                        .buttonStyle(ARGlassPillStyle())
                        .accessibilityHint("Clears all points")
                }
            case .saved:
                savedCard
            }
        }
    }

    private var savedCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SAVED TO \((saved?.projectName ?? "History").uppercased())")
                        .pmCaptionStyle(tracking: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(saved?.name ?? "")
                        .font(.pm(16, .semibold))
                        .foregroundStyle(PM.Colors.textPrimary)
                }
                Spacer(minLength: 8)
                Text(unit.format(metres: saved?.metres ?? 0))
                    .font(.pm(24, .regular))
                    .monospacedDigit()
                    .foregroundStyle(PM.Colors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                Button(saved?.projectID != nil ? "View project" : "View history") {
                    if let id = saved?.projectID { router.push(.project(projectID: id)) } else { router.select(.history) }
                }
                .buttonStyle(PMSecondaryButtonStyle(height: 48, fontSize: 15, fillWidth: true))
                Button("Measure again") { reset() }
                    .buttonStyle(PMPrimaryButtonStyle(height: 48, fontSize: 15))
            }
        }
        .padding(16)
        .pmCard(radius: 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Actions

    private func advanceByTap() {
        switch step {
        case .ready, .measuring: place()
        default: break
        }
    }

    private func place() {
        if var f = fixture {
            Haptics.arEndpointPlaced()
            f.step = f.step == .ready ? .measuring : f.step == .measuring ? .done : f.step
            withAnimation(PM.Motion.normal) { fixture = f }
            return
        }
        withAnimation(PM.Motion.normal) {
            if session.placePoint() { pendingAdd = false }
        }
    }

    private func undo() {
        if var f = fixture {
            f.step = f.step == .done ? .measuring : .ready
            withAnimation(PM.Motion.normal) { fixture = f }
            return
        }
        withAnimation(PM.Motion.normal) { session.undo() }
    }

    /// Keep the finished segments on screen and start a new one.
    private func addAnother() {
        if var f = fixture {
            f.step = .ready
            withAnimation(PM.Motion.normal) { fixture = f }
            return
        }
        // The finished segments stay on screen (unsaved); the next "Start point" begins another.
        withAnimation(PM.Motion.normal) { pendingAdd = true }
    }

    private func reset() {
        withAnimation(PM.Motion.normal) {
            showToast = false
            saved = nil
            pendingAdd = false
            if var f = fixture { f.step = .ready; fixture = f }
            session.clear()
        }
    }

    private func save() {
        let project = targetProject
        let now = Date()
        var lastName = "", lastMetres = 0.0
        if fixture != nil {
            lastName = "Counter length"
            lastMetres = fixtureFinal
            store.add(MeasurementRecord(name: lastName, value: ARUnit.m.format(metres: lastMetres),
                                        source: .arDerived, tool: .ar, projectID: project?.id, date: now))
        } else {
            let toSave = session.unsaved
            guard !toSave.isEmpty else { return }
            for (i, seg) in toSave.enumerated() {
                guard let m = seg.metres else { continue }
                lastName = toSave.count == 1 ? "AR distance" : "AR distance \(i + 1)"
                lastMetres = m
                store.add(MeasurementRecord(name: lastName, value: ARUnit.m.format(metres: m),
                                            source: .arDerived, tool: .ar, projectID: project?.id, date: now))
            }
            session.markSaved()
        }
        withAnimation(PM.Motion.normal) {
            saved = SavedSummary(projectName: project?.name, projectID: project?.id, name: lastName, metres: lastMetres)
            showToast = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(PM.Motion.normal) { showToast = false }
        }
    }
}

/// Start / End point: mint when a point can be placed, muted while there's no surface or tracking.
private struct ARPlaceButtonStyle: ButtonStyle {
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(17, .bold))
            .foregroundStyle(enabled ? PM.Colors.onAccent : ARChrome.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Capsule().fill(enabled ? (configuration.isPressed ? PM.Colors.accentPressed : PM.Colors.accent) : ARChrome.glassStrong))
            .overlay(Capsule().strokeBorder(enabled ? Color.clear : ARChrome.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Live and secondary distance label: 34 tall glass pill, 18 medium.
private struct ARDistanceChip: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.pm(18, .medium))
            .monospacedDigit()
            .foregroundStyle(ARChrome.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(Color(hex: 0x0B0D0F, opacity: 0.82)))
            .overlay(Capsule().strokeBorder(ARChrome.line, lineWidth: 1))
            .fixedSize()
            .allowsHitTesting(false)
    }
}

/// Final distance card with the AR-derived source line.
private struct ARFinalCard: View {
    var value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.pm(30, .regular))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(ARChrome.text)
            Text(SourceKind.arDerived.rawValue)
                .font(.pm(12, .semibold))
                .foregroundStyle(ARChrome.textSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x0B0D0F, opacity: 0.88)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ARChrome.mint, lineWidth: 1))
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Distance \(value), AR-derived")
    }
}

/// Shown when the AR session fails for a reason other than permission or support.
private struct ARFailureCard: View {
    var message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PMIcon(.warning, size: 16, stroke: 2.2).foregroundStyle(PM.Colors.warning)
                Text("AR stopped").font(.pm(15, .bold)).foregroundStyle(PM.Colors.textPrimary)
            }
            Text(message).font(.pm(13)).foregroundStyle(PM.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: onRetry)
                .buttonStyle(PMSecondaryButtonStyle(height: 44, fontSize: 15, fillWidth: true))
        }
        .padding(16)
        .pmCard(radius: 22)
    }
}

// MARK: - Pieces

/// Dark scrim behind the bottom controls so hint text and buttons stay legible over any camera scene.
/// Extends 120 pt above the controls and down to the screen edge; never takes touches.
private struct ARBottomScrim: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Color(hex: 0x060809, opacity: 0), location: 0),
            .init(color: Color(hex: 0x060809, opacity: 0.55), location: 0.4),
            .init(color: Color(hex: 0x060809, opacity: 0.8), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .padding(.top, -120)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Glass hint pill over the camera: 44 tall, 16 semibold.
private struct ARHintPill<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: spacing) { content }
            .font(.pm(16, .semibold))
            .foregroundStyle(ARChrome.text)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Capsule().fill(ARChrome.glassStrong))
            .accessibilityElement(children: .combine)
    }
}

private struct ARUnitPicker: View {
    @Binding var unit: ARUnit

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ARUnit.allCases, id: \.self) { u in
                let on = u == unit
                Button {
                    Haptics.selection()
                    withAnimation(.easeOut(duration: 0.2)) { unit = u }
                } label: {
                    Text(u.rawValue)
                        .font(.pm(14, on ? .bold : .semibold))
                        .foregroundStyle(on ? Color(hex: 0x0B0D0F) : ARChrome.textSecondary)
                        .frame(minWidth: 48)
                        .frame(height: 36)
                        .background(Capsule().fill(on ? ARChrome.text : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(ARChrome.glassStrong))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Units")
    }
}

/// Scanning grid: 1 pt lines every 32 pt; rows at 10% and columns at 5% white.
private struct ARScanGrid: View {
    var body: some View {
        Canvas { ctx, size in
            var rows = Path()
            var y: CGFloat = 0
            while y < size.height { rows.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 32 }
            ctx.fill(rows, with: .color(Color(hex: 0xF1F4F3, opacity: 0.10)))
            var cols = Path()
            var x: CGFloat = 0
            while x < size.width { cols.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 32 }
            ctx.fill(cols, with: .color(Color(hex: 0xF1F4F3, opacity: 0.05)))
        }
        .allowsHitTesting(false)
    }
}

/// Feature points twinkling while tracking starts (2.8 s cycle, staggered by 0.2 s).
private struct ARParticles: View {
    var scale: CGFloat
    var animate: Bool

    private static let points: [CGPoint] = [
        CGPoint(x: 40, y: 290), CGPoint(x: 92, y: 300), CGPoint(x: 150, y: 285), CGPoint(x: 210, y: 296),
        CGPoint(x: 270, y: 288), CGPoint(x: 330, y: 300), CGPoint(x: 60, y: 380), CGPoint(x: 130, y: 420),
        CGPoint(x: 200, y: 360), CGPoint(x: 260, y: 440), CGPoint(x: 320, y: 400), CGPoint(x: 80, y: 480),
        CGPoint(x: 180, y: 470), CGPoint(x: 300, y: 500)
    ]

    var body: some View {
        TimelineView(.animation(paused: !animate)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(Self.points.indices, id: \.self) { i in
                    let p = Self.points[i]
                    Circle()
                        .fill(i % 3 == 0 ? Color(hex: 0x4CC3F5) : .white)
                        .frame(width: 3, height: 3)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .opacity(animate ? Self.twinkle(t - Double(i) * 0.2) : 0.6)
                        .offset(x: p.x * scale, y: p.y * scale)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Keyframes 0% → 0, 40% → 0.8, 100% → 0, eased.
    private static func twinkle(_ t: Double) -> Double {
        let phase = ((t.truncatingRemainder(dividingBy: 2.8)) + 2.8).truncatingRemainder(dividingBy: 2.8) / 2.8
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        return phase < 0.4 ? 0.8 * ease(phase / 0.4) : 0.8 * (1 - ease((phase - 0.4) / 0.6))
    }
}

/// Detected benchtop plane: mint fill, 26 pt stripes, bright 2 pt bottom edge.
private struct ARPlaneHighlight: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x52F2B8, opacity: 0.24)
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = 0
                while x < size.width { p.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 26 }
                ctx.fill(p, with: .color(Color(hex: 0x52F2B8, opacity: 0.35)))
            }
            Color(hex: 0x52F2B8, opacity: 0.7).frame(height: 2)
        }
        .clipShape(TrapezoidShape(inset: 0.025))
        .allowsHitTesting(false)
    }
}

/// Placement reticle: 44 pt white ring with dark keylines and a soft outer halo.
private struct ARReticle: View {
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.22), lineWidth: 7).frame(width: 51, height: 51)
            Circle().stroke(Color.black.opacity(0.55), lineWidth: 1.5).frame(width: 45.5, height: 45.5)
            Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: 44, height: 44)
            Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5).frame(width: 40, height: 40)
            Circle().fill(Color.white).frame(width: 6, height: 6)
            Circle().stroke(Color.black.opacity(0.55), lineWidth: 1.5).frame(width: 7.5, height: 7.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ARMeasureLine: View {
    var from: CGPoint
    var to: CGPoint

    var body: some View {
        Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }
        .stroke(ARChrome.mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .shadow(color: ARChrome.mint.opacity(0.6), radius: 4)
        .allowsHitTesting(false)
    }
}

private struct ARPoint: View {
    var body: some View {
        Circle().fill(ARChrome.mint)
            .frame(width: 14, height: 14)
            .shadow(color: ARChrome.mint.opacity(0.8), radius: 7)
            .allowsHitTesting(false)
    }
}

/// Start-point halo: scale 1 → 2.2 and opacity 0.6 → 0 over 1.8 s, repeating.
private struct ARHalo: View {
    var animate: Bool
    @State private var on = false

    var body: some View {
        Circle().fill(ARChrome.mint.opacity(0.5))
            .frame(width: 18, height: 18)
            .scaleEffect(on ? 2.2 : 1)
            .opacity(on ? 0 : 0.6)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { on = true }
            }
            .allowsHitTesting(false)
    }
}

/// Measurement info for AR, in the style of the level's info panel.
private struct ARInfoPanel: View {
    var rows: [(String, String)]
    var good: Bool

    var body: some View {
        ToolChromeInfoPanel(rows: rows, quality: good ? "Good" : "Limited")
    }
}

#Preview {
    ARMeasureView()
        .environment(Router())
}
