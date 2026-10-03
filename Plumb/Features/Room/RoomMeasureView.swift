//
//  RoomMeasureView.swift
//  Plumb
//
//  Room Measure (board 14): scan in progress → floor plan result, or an honest "couldn't detect" state.
//  Nothing is estimated or filled in: the plan only shows what the scan found.
//

import SwiftUI

enum RoomPhase: Equatable { case scanning, result, failed }

struct RoomMeasureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    @State private var phase: RoomPhase
    @State private var stepIndex = 2          // "Detect walls" is measuring, as drawn
    @State private var paused = false

    init(startPhase: RoomPhase = .scanning) {
        _phase = State(initialValue: startPhase)
    }

    var body: some View {
        ZStack {
            switch phase {
            case .scanning:
                RoomScanView(stepIndex: stepIndex, paused: $paused, onClose: { dismiss() })
                    .transition(.opacity)
            case .result:
                RoomResultView(onBack: { withAnimation(PM.Motion.normal) { restart() } })
                    .transition(.opacity)
            case .failed:
                RoomFailedView(onClose: { dismiss() },
                               onRetry: { withAnimation(PM.Motion.normal) { restart() } },
                               onAR: { router.push(.ar) })
                    .transition(.opacity)
            }
        }
        .task(id: TaskKey(phase: phase, paused: paused)) { await runScan() }
    }

    private struct TaskKey: Equatable { var phase: RoomPhase; var paused: Bool }

    /// Simulated scan: remaining steps complete one by one, then the floor plan appears.
    private func runScan() async {
        guard phase == .scanning, !paused else { return }
        while stepIndex < RoomScanView.steps.count {
            try? await Task.sleep(for: .seconds(1.6))
            if Task.isCancelled { return }
            withAnimation(PM.Motion.normal) { stepIndex += 1 }
        }
        try? await Task.sleep(for: .seconds(0.4))
        if Task.isCancelled { return }
        Haptics.calibrationComplete()
        withAnimation(PM.Motion.normal) { phase = .result }
    }

    private func restart() {
        stepIndex = 0
        paused = false
        phase = .scanning
    }
}

// MARK: - Camera backdrop

/// Kitchen seen from a corner: a 46 pt side wall, the kitchen and the tiled floor, as on the board.
private struct RoomCameraBackdrop: View {
    var dimmed = false

    var body: some View {
        GeometryReader { g in
            let s = g.size.width / PM.Board.width
            ZStack(alignment: .topLeading) {
                Group {
                    KitchenScene().sceneBox(46 * s, -60 * s, 344 * s, 438 * s)
                    LinearGradient(colors: [Color(hex: 0xB9B1A4), Color(hex: 0xCEC6B9)], startPoint: .leading, endPoint: .trailing)
                        .sceneBox(0, 0, 46 * s, 378 * s)
                    KitchenFloorScene().sceneBox(0, 378 * s, g.size.width, max(g.size.height - 378 * s, 466 * s))
                }
                .sceneFilter(brightness: dimmed ? 0.34 : 1, saturate: dimmed ? 0.8 : 1)
                CameraVignette(bottomHeight: 120)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .background(ARChrome.cameraBase.ignoresSafeArea())
    }
}

/// Close · title · tracking pill, over the camera.
private struct RoomCameraTopBar: View {
    var tracking: ARTrackingQuality
    var onClose: () -> Void

    var body: some View {
        HStack {
            ARGlassButton(icon: .close, label: "Close Room Measure", action: onClose)
            Spacer()
            ARTitlePill(title: "Room Measure")
            Spacer()
            HStack(spacing: 5) {
                if tracking == .limited { PMIcon(.warning, size: 12, stroke: 2.4) } else { PMIcon(.check, size: 12, stroke: 2.6) }
                Text(tracking == .limited ? "Limited" : "Good")
            }
            .font(.pm(12, .bold))
            .foregroundStyle(tracking.color)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(ARChrome.glassStrong))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tracking \(tracking == .limited ? "limited" : "good")")
        }
        .padding(.horizontal, 20)
        .padding(.top, 56 - PM.Board.statusBar)
    }
}

// MARK: - Scanning

private struct RoomScanView: View {
    static let steps = ["Scan room", "Detect floor", "Detect walls", "Detect corners", "Create outline"]

    var stepIndex: Int
    @Binding var paused: Bool
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Progress bar: 48% with step 3 active, as drawn.
    private var progress: CGFloat {
        min(1, (CGFloat(stepIndex) + 0.4) / CGFloat(Self.steps.count))
    }

    var body: some View {
        ZStack {
            RoomCameraBackdrop()
            overlays
            GeometryReader { g in
                VStack(spacing: 0) {
                    RoomCameraTopBar(tracking: .good, onClose: onClose)
                    Spacer(minLength: 0)
                    sheet
                        .padding(.horizontal, 12)
                        .padding(.bottom, g.safeAreaInsets.bottom > 0 ? 16 - PM.Board.homeIndicator + g.safeAreaInsets.bottom : 16)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .environment(\.colorScheme, .dark)
    }

    /// Detected floor grid, wall edges and the blinking corner, in board coordinates.
    private var overlays: some View {
        GeometryReader { g in
            let s = g.size.width / PM.Board.width
            ZStack(alignment: .topLeading) {
                ZStack {
                    Color(hex: 0x52F2B8, opacity: 0.20)
                    Canvas { ctx, size in
                        var p = Path()
                        var y: CGFloat = 0
                        while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 30 }
                        var x: CGFloat = 0
                        while x < size.width { p.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 30 }
                        ctx.fill(p, with: .color(Color(hex: 0x52F2B8, opacity: 0.40)))
                    }
                }
                .clipShape(TrapezoidShape(inset: 0.12))
                .sceneBox(0, 380 * s, g.size.width, 170 * s)

                Color(hex: 0x4CC3F5, opacity: 0.8).sceneBox(46 * s, 200 * s, 2, 180 * s)
                Color(hex: 0x4CC3F5, opacity: 0.8).sceneBox(46 * s, 378 * s, 298 * s, 2)
                RoomBlinkDot(animate: !reduceMotion)
                    .position(x: 47 * s, y: 379 * s)

                Text("Slowly pan across each wall")
                    .font(.pm(15, .semibold))
                    .foregroundStyle(ARChrome.text)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Capsule().fill(ARChrome.glassStrong))
                    .fixedSize()
                    .position(x: g.size.width / 2, y: (300 + 20) * s)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Scanning room").font(.pm(18, .bold)).foregroundStyle(PM.Colors.textPrimary)
                Spacer()
                Text("Step \(min(stepIndex + 1, Self.steps.count)) of \(Self.steps.count)")
                    .font(.pm(13))
                    .monospacedDigit()
                    .foregroundStyle(PM.Colors.textSecondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(PM.Colors.border)
                    Rectangle().fill(PM.Colors.measuring).frame(width: g.size.width * progress)
                }
                .clipShape(Capsule())
            }
            .frame(height: 4)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                ForEach(Self.steps.indices, id: \.self) { i in
                    stepRow(i)
                }
            }

            Button(paused ? "Resume scan" : "Pause scan") { paused.toggle() }
                .buttonStyle(PMSecondaryButtonStyle(height: 48, fontSize: 15, fillWidth: true))
        }
        .padding(18)
        .pmCard(radius: 30)
    }

    private func stepRow(_ i: Int) -> some View {
        let state: Int = i < stepIndex ? 0 : (i == stepIndex ? 1 : 2) // done, active, waiting
        let status = state == 0 ? "Done" : state == 1 ? (paused ? "Paused" : "Measuring") : "Waiting"
        return HStack(spacing: 12) {
            ZStack {
                switch state {
                case 0:
                    Circle().fill(PM.Colors.accent)
                    PMIcon(.check, size: 12, stroke: 3).foregroundStyle(PM.Colors.onAccent)
                case 1:
                    Circle().strokeBorder(PM.Colors.measuring, lineWidth: 2)
                default:
                    Circle().strokeBorder(PM.Colors.tickMinor, lineWidth: 1.5)
                }
            }
            .frame(width: 22, height: 22)
            Text(Self.steps[i])
                .font(.pm(15, .medium))
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Fixed trailing slot, swapped without a crossfade: fading "Measuring" out under "Done"
            // left a truncated "Meas…" visible behind the new label.
            Text(status)
                .font(.pm(12, .bold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(state == 0 ? PM.Colors.accent : state == 1 ? PM.Colors.measuring : PM.Colors.textTertiary)
                .contentTransition(.identity)
                .frame(minWidth: 72, alignment: .trailing)
                .transaction(value: status) { $0.animation = nil }
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }
}

/// Corner marker blinking 1 ↔ 0.35 over 1.4 s.
private struct RoomBlinkDot: View {
    var animate: Bool
    @State private var dim = false

    var body: some View {
        Circle().fill(Color(hex: 0x4CC3F5))
            .frame(width: 14, height: 14)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

// MARK: - Result

private struct RoomResultView: View {
    var onBack: () -> Void
    @Environment(Router.self) private var router

    /// Plan scale on the board: 286 pt = 4.82 m, 220 pt = 3.71 m (59.3 pt per metre).
    private static let ptPerMetre: CGFloat = 286 / 4.82
    private static let minMetres: CGFloat = 1.0

    @State private var widthM: Double = 4.82
    @State private var lengthM: Double = 3.71
    @State private var history: [(Double, Double)] = []
    @State private var future: [(Double, Double)] = []
    @State private var editing = false
    @State private var dragStart: (Double, Double)?
    @State private var toast: String?

    private var area: Double { widthM * lengthM }
    private var kitchen: Project? {
        let store = MeasurementStore.shared
        return store.projects.first { $0.name == "Kitchen Renovation" } ?? store.projects.first
    }

    var body: some View {
        ZStack(alignment: .top) {
            PM.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                plan
                    .padding(.top, 124 - 100)
                summary
                    .padding(.top, 452 - 434)
                HStack(spacing: 8) {
                    Button { router.push(.ar) } label: {
                        HStack(spacing: 8) { PMIcon(.plus, size: 16, stroke: 2); Text("Add measurement") }
                    }
                    .buttonStyle(PMSecondaryButtonStyle(height: 44, fontSize: 14, horizontalPadding: 8, fillWidth: true))
                    Button { withAnimation(PM.Motion.normal) { editing.toggle() } } label: {
                        HStack(spacing: 8) { PMIcon(editing ? .check : .pencil, size: 16, stroke: 1.8); Text(editing ? "Done editing" : "Edit point") }
                    }
                    .buttonStyle(PMSecondaryButtonStyle(height: 44, fontSize: 14, horizontalPadding: 8, fillWidth: true))
                }
                .padding(.horizontal, 20)
                .padding(.top, 59)
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    Button("Save project") { save() }
                        .buttonStyle(PMPrimaryButtonStyle(height: 56, fontSize: 16))
                    Button("Export PDF") {
                        if let id = kitchen?.id { router.push(.report(projectID: id)) }
                    }
                    .buttonStyle(PMSecondaryButtonStyle(height: 56, fontSize: 16, fillWidth: true))
                }
                .padding(.horizontal, 20)
            }

            if let toast {
                ToastView(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var topBar: some View {
        HStack {
            IconCircleButton(icon: .back, label: "Back", iconSize: 18, stroke: 2, action: onBack)
            Spacer()
            HStack(spacing: 6) {
                IconCircleButton(icon: .undo, label: "Undo", iconSize: 18, stroke: 1.8) { undo() }
                    .disabled(history.isEmpty)
                    .opacity(history.isEmpty ? 0.5 : 1)
                IconCircleButton(icon: .redo, label: "Redo", iconSize: 18, stroke: 1.8) { redo() }
                    .disabled(future.isEmpty)
                    .opacity(future.isEmpty ? 0.5 : 1)
            }
        }
        .overlay {
            Text("Room").font(.pmNavTitle).foregroundStyle(PM.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56 - PM.Board.statusBar)
    }

    /// 350 × 310 plan card with a 20 pt grid; the outline keeps its top-left corner at (32, 50).
    private var plan: some View {
        let w = CGFloat(widthM) * Self.ptPerMetre
        let h = CGFloat(lengthM) * Self.ptPerMetre
        let origin = CGPoint(x: 32, y: 50)
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                var p = Path()
                var y: CGFloat = 0
                while y < size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 20 }
                var x: CGFloat = 0
                while x < size.width { p.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 20 }
                ctx.fill(p, with: .color(Color.white.opacity(0.03)))
            }

            Rectangle()
                .fill(PM.Colors.accent.opacity(0.05))
                .overlay(Rectangle().strokeBorder(PM.Colors.accent, lineWidth: 2))
                .sceneBox(origin.x, origin.y, w, h)

            Text("FLOOR · \(String(format: "%.1f", area)) m²")
                .font(.pm(12, .bold))
                .tracking(1.2)
                .foregroundStyle(PM.Colors.textSecondary)
                .fixedSize()
                .position(x: origin.x + w / 2, y: origin.y + h / 2 - 3)

            RoomDimensionChip(text: String(format: "%.2f m", widthM))
                .position(x: origin.x + w / 2, y: 18 + 12)
            RoomDimensionChip(text: String(format: "%.2f m", lengthM))
                .rotationEffect(.degrees(90))
                .position(x: origin.x + w, y: origin.y + h / 2)

            // Corner handles; the bottom-right one resizes while editing.
            ForEach(0..<4, id: \.self) { i in
                let pt = CGPoint(x: origin.x + (i % 2 == 0 ? 0 : w), y: origin.y + (i < 2 ? 0 : h))
                Circle()
                    .fill(PM.Colors.textPrimary)
                    .frame(width: 12, height: 12)
                    .overlay {
                        if editing && i == 3 {
                            Circle().strokeBorder(PM.Colors.accent, lineWidth: 2).frame(width: 28, height: 28)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .position(pt)
                    .gesture(i == 3 && editing ? resizeGesture : nil)
                    .accessibilityHidden(i != 3 || !editing)
            }
        }
        .frame(width: 350, height: 310, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(PM.Colors.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(PM.Colors.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Floor plan, \(String(format: "%.2f", widthM)) by \(String(format: "%.2f", lengthM)) metres")
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                if dragStart == nil { dragStart = (widthM, lengthM) }
                guard let start = dragStart else { return }
                let maxW = Double((350 - 32 - 20) / Self.ptPerMetre)
                let maxL = Double((310 - 50 - 20) / Self.ptPerMetre)
                widthM = min(maxW, max(Self.minMetres, start.0 + Double(v.translation.width / Self.ptPerMetre)))
                lengthM = min(maxL, max(Self.minMetres, start.1 + Double(v.translation.height / Self.ptPerMetre)))
                // Honest precision: 1 cm.
                widthM = (widthM * 100).rounded() / 100
                lengthM = (lengthM * 100).rounded() / 100
            }
            .onEnded { _ in
                if let start = dragStart, start != (widthM, lengthM) {
                    history.append(start)
                    future.removeAll()
                }
                dragStart = nil
            }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ROOM").font(.pm(12, .heavy)).tracking(1.4).foregroundStyle(PM.Colors.textSecondary)
                Spacer()
                Text("AR-derived · 4 corners detected").font(.pm(12, .semibold)).foregroundStyle(PM.Colors.textSecondary)
            }
            Text("\(String(format: "%.2f", widthM)) m × \(String(format: "%.2f", lengthM)) m")
                .font(.pm(32, .light))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline) {
                Text("Area").font(.pm(15)).foregroundStyle(PM.Colors.textSecondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(String(format: "%.1f", area)) m²").font(.pm(20, .medium)).monospacedDigit()
                        .foregroundStyle(PM.Colors.textPrimary)
                    Text("CALCULATED").font(.pm(12, .bold)).foregroundStyle(PM.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmCard(radius: 24)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        future.append((widthM, lengthM))
        withAnimation(PM.Motion.normal) { (widthM, lengthM) = last }
    }

    private func redo() {
        guard let next = future.popLast() else { return }
        history.append((widthM, lengthM))
        withAnimation(PM.Motion.normal) { (widthM, lengthM) = next }
    }

    private func save() {
        let store = MeasurementStore.shared
        let project = kitchen ?? store.addProject(named: "Room")
        let now = Date()
        store.measurements.append(MeasurementRecord(name: "Room width", value: String(format: "%.2f m", widthM),
                                                    source: .arDerived, tool: .room, projectID: project.id, date: now))
        store.measurements.append(MeasurementRecord(name: "Room length", value: String(format: "%.2f m", lengthM),
                                                    source: .arDerived, tool: .room, projectID: project.id, date: now))
        store.add(MeasurementRecord(name: "Floor area", value: String(format: "%.1f m²", area),
                                    source: .calculated, tool: .room, projectID: project.id, date: now))
        withAnimation(PM.Motion.normal) { toast = "Saved to \(project.name)" }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(PM.Motion.normal) { toast = nil }
        }
    }
}

/// Dimension chip on the plan: 24 tall, raised fill, 13 semibold.
private struct RoomDimensionChip: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.pm(13, .semibold))
            .monospacedDigit()
            .foregroundStyle(PM.Colors.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(PM.Colors.surfaceRaised))
            .fixedSize()
    }
}

// MARK: - Failed

private struct RoomFailedView: View {
    var onClose: () -> Void
    var onRetry: () -> Void
    var onAR: () -> Void

    private let reasons = ["The room is too dark", "Walls are plain, with little visual detail", "The phone moved too quickly"]

    var body: some View {
        ZStack {
            RoomCameraBackdrop(dimmed: true)
            GeometryReader { g in
                VStack(spacing: 0) {
                    RoomCameraTopBar(tracking: .limited, onClose: onClose)
                    Spacer(minLength: 0)
                    card
                        .padding(.horizontal, 12)
                        .padding(.bottom, g.safeAreaInsets.bottom > 0 ? 16 - PM.Board.homeIndicator + g.safeAreaInsets.bottom : 16)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .environment(\.colorScheme, .dark)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            PMIcon(.warning, size: 24, stroke: 1.8)
                .foregroundStyle(PM.Colors.warning)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x2A2213)))
            Text("We couldn’t detect the walls reliably")
                .font(.pm(22, .bold))
                .tracking(-0.3)
                .foregroundStyle(PM.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Room Measure only draws what it can see. Nothing has been estimated or filled in.")
                .font(.pm(15))
                .lineSpacing(15 * 0.45 - 3)
                .foregroundStyle(PM.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(reasons, id: \.self) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("–").foregroundStyle(PM.Colors.warning)
                        Text(r).foregroundStyle(PM.Colors.textPrimary)
                    }
                    .font(.pm(15))
                }
            }
            Button("Try again", action: onRetry)
                .buttonStyle(PMPrimaryButtonStyle(height: 54, fontSize: 16))
            Button("Measure walls with AR Measure", action: onAR)
                .buttonStyle(PMSecondaryButtonStyle(height: 54, fontSize: 15, fillWidth: true))
        }
        .padding(.top, 22)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .pmCard(radius: 30)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Scanning") { RoomMeasureView().environment(Router()) }
#Preview("Result") { RoomMeasureView(startPhase: .result).environment(Router()) }
#Preview("Failed") { RoomMeasureView(startPhase: .failed).environment(Router()) }
