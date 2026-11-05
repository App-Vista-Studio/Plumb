//
//  RulerView.swift
//  Plumb
//
//  Ruler board: on-screen ruler down the left edge with markers A and B.
//  Honest precision: 1 mm (1/16 in in inch mode). The scale comes from the device's published
//  pixel density, or from the user's own card calibration when the model is unknown.
//

import SwiftUI
import UIKit

struct RulerView: View {
    enum Unit: String, Hashable { case cm, mm, inch }
    enum Marker { case a, b }

    // Persisted so leaving the screen (or the app) doesn't lose the reading.
    @AppStorage("ruler.unit") private var unitRaw = Unit.cm.rawValue
    /// Marker positions in millimetres from the top of the ruler.
    @AppStorage("ruler.a") private var a: Double = 0
    @AppStorage("ruler.b") private var b: Double = 94
    @AppStorage(RulerScreenScale.calibrationKey) private var calibratedPtPerMM: Double = 0

    @Environment(Router.self) private var router
    @Environment(\.displayScale) private var displayScale

    @State private var dragging: Marker?
    @State private var dragStartMM: Double = 0
    @State private var nextTap: Marker = .a
    @State private var locked = false
    @State private var showToast = false
    @State private var showCalibration = false

    private var unit: Unit { Unit(rawValue: unitRaw) ?? .cm }
    private var unitBinding: Binding<Unit> {
        Binding(get: { unit }, set: { unitRaw = $0.rawValue })
    }

    private var scale: RulerScreenScale {
        RulerScreenScale.resolve(calibrated: calibratedPtPerMM, fallbackScale: displayScale)
    }

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            let fullHeight = geo.size.height + top + bottom
            let width = geo.size.width
            // Board y values assume a 47 pt status bar: the ruler starts at y 116.
            let rulerTop = top + (116 - PM.Board.statusBar)
            let px = scale.pointsPerMM
            let rulerHeight = max(0, fullHeight - rulerTop)
            let maxMM = max(10, Double(rulerHeight / px).rounded(.down))

            ZStack(alignment: .topLeading) {
                PM.Colors.background

                RulerStrip(unit: unit, px: px, maxMM: maxMM, a: a, b: b)
                    .frame(width: 96, height: rulerHeight)
                    .offset(y: rulerTop)

                RulerMarkers(px: px, a: a, b: b, width: width)
                    .frame(width: width, height: rulerHeight)
                    .offset(y: rulerTop)
                    .allowsHitTesting(false)

                // Touch area over the ruler and marker chips.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 140, height: rulerHeight)
                    .gesture(markerGesture(px: px, maxMM: maxMM))
                    .accessibilityElement()
                    .accessibilityLabel("Ruler, marker B")
                    .accessibilityValue("Distance A to B \(spokenDistance)")
                    .accessibilityHint(locked ? "Locked" : "Swipe up or down to move marker B by one step")
                    .accessibilityAdjustableAction { dir in
                        guard !locked else { return }
                        b = clampMM(b + (dir == .increment ? step : -step), maxMM: maxMM)
                    }
                    .offset(y: rulerTop)

                // Header sits on the background above the ruler.
                PMTopBar(title: "Ruler", topPadding: top + (58 - PM.Board.statusBar),
                         leading: { BackButton() },
                         trailing: {
                             IconCircleButton(icon: .calibrate, label: "Screen size settings") { showCalibration = true }
                         })
                .padding(.bottom, 10)
                .frame(width: width)
                .background(PM.Colors.background)

                rightColumn(maxMM: maxMM)
                    .frame(width: max(0, width - 150 - 18), alignment: .leading)
                    .offset(x: 150, y: top + (150 - PM.Board.statusBar))

                HStack(spacing: 8) {
                    ToolChromeLockButton(locked: locked, fontSize: 16, iconSize: 17) {
                        locked.toggle()
                        if locked { Haptics.measurementLocked() }
                    }
                    Button("Save", action: save)
                        .buttonStyle(PMSecondaryButtonStyle(horizontalPadding: 18))
                }
                .frame(width: max(0, width - 150 - 18))
                .offset(x: 150, y: fullHeight - max(bottom, 20) - 54)
            }
            .frame(width: width, height: fullHeight, alignment: .topLeading)
            .ignoresSafeArea()
            .onAppear {
                // A new device or calibration can shrink the ruler; keep markers on it.
                a = clampMM(a, maxMM: maxMM)
                b = clampMM(b, maxMM: maxMM)
            }
        }
        .overlay { if locked { ToolChromeLockedFrame() } }
        .toolChromeToast($showToast)
        .animation(dragging == nil ? PM.Motion.spatial(0.2) : nil, value: a)
        .animation(dragging == nil ? PM.Motion.spatial(0.2) : nil, value: b)
        .sheet(isPresented: $showCalibration) {
            RulerCalibrationSheet(calibratedPtPerMM: $calibratedPtPerMM, modelScale: RulerScreenScale.modelScale)
                .presentationDetents([.large])
        }
    }

    // MARK: Right column

    private func rightColumn(maxMM: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DISTANCE A → B")
                    .font(.pm(12, .heavy)).tracking(1.4)
                    .foregroundStyle(PM.Colors.textSecondary)
                Text(distanceText)
                    .font(.pm(50, .light))
                    .tracking(-1.2)
                    .monospacedDigit()
                    .foregroundStyle(PM.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .cssLineBox(fontSize: 50, lineHeight: 1.05)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Circle().fill(scale.isTrusted ? PM.Colors.textSecondary : PM.Colors.warning).frame(width: 6, height: 6)
                    Text(scale.isTrusted ? "Screen scale · \(scale.modelName)" : "Screen scale not calibrated")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.pm(12, .semibold))
                .foregroundStyle(scale.isTrusted ? PM.Colors.textSecondary : PM.Colors.warning)
            }

            PMSegmented(options: [(Unit.cm, "cm"), (Unit.mm, "mm"), (Unit.inch, "in")], selection: unitBinding,
                        fontSize: 14, fontWeight: .bold, tracking: 0, fitContent: true, trackPadding: 5)

            VStack(alignment: .leading, spacing: 8) {
                Text("MOVE MARKER B")
                    .font(.pm(12, .heavy)).tracking(1.2)
                    .foregroundStyle(PM.Colors.textSecondary)
                HStack(spacing: 8) {
                    Button(unit == .inch ? "\u{2212} \u{215F}\u{2081}\u{2086}" : "\u{2212} 1 mm") { nudge(-1, maxMM: maxMM) }
                        .buttonStyle(RulerStepStyle())
                        .accessibilityLabel(unit == .inch ? "Move B up one sixteenth of an inch" : "Move B up 1 mm")
                    Button(unit == .inch ? "+ \u{215F}\u{2081}\u{2086}" : "+ 1 mm") { nudge(1, maxMM: maxMM) }
                        .buttonStyle(RulerStepStyle())
                        .accessibilityLabel(unit == .inch ? "Move B down one sixteenth of an inch" : "Move B down 1 mm")
                }
                .disabled(locked)
                Text("Or drag a marker on the ruler. Tap the ruler to place A, then B.")
                    .font(.pm(12))
                    .lineSpacing(12 * 0.4 - 2.3)
                    .foregroundStyle(PM.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    PMIcon(.info, size: 15, stroke: 1.9)
                    Text("Screen ruler")
                }
                .font(.pm(13, .bold))
                .foregroundStyle(PM.Colors.textPrimary)
                Text(scale.isTrusted
                     ? "Accurate on supported iPhone and iPad models with the correct screen size set. For larger objects use AR Measure."
                     : "This model isn't in Plumb's screen table. Calibrate with a bank card for an accurate ruler.")
                    .font(.pm(12))
                    .lineSpacing(12 * 0.45 - 2.3)
                    .foregroundStyle(PM.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if scale.isTrusted {
                    Button("Open AR Measure") { router.push(.ar) }
                        .font(.pm(13, .bold))
                        .foregroundStyle(PM.Colors.accent)
                        .buttonStyle(.plain)
                } else {
                    Button("Calibrate screen") { showCalibration = true }
                        .font(.pm(13, .bold))
                        .foregroundStyle(PM.Colors.accent)
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .pmCard(radius: PM.Radius.cardSmall)
        }
    }

    // MARK: Values

    /// One snapping step in millimetres: 1 mm, or 1/16 in in inch mode.
    private var step: Double { unit == .inch ? 25.4 / 16 : 1 }

    private var distanceMM: Double { abs(b - a) }

    private var distanceText: String {
        switch unit {
        case .cm: String(format: "%.1f cm", distanceMM / 10)
        case .mm: "\(Int(distanceMM.rounded())) mm"
        case .inch: String(format: "%.2f in", distanceMM / 25.4)
        }
    }

    private var spokenDistance: String {
        switch unit {
        case .cm: String(format: "%.1f centimetres", distanceMM / 10)
        case .mm: "\(Int(distanceMM.rounded())) millimetres"
        case .inch: String(format: "%.2f inches", distanceMM / 25.4)
        }
    }

    private func snap(_ mm: Double) -> Double { (mm / step).rounded() * step }

    private func clampMM(_ mm: Double, maxMM: Double) -> Double {
        guard mm.isFinite else { return 0 }
        return min(maxMM, max(0, mm))
    }

    private func nudge(_ dir: Double, maxMM: Double) {
        guard !locked else { return }
        b = clampMM(snap(b) + dir * step, maxMM: maxMM)
    }

    private func markerGesture(px: CGFloat, maxMM: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard !locked, px > 0 else { return }
                if dragging == nil {
                    guard hypot(v.translation.width, v.translation.height) > 4 else { return }
                    let startMM = Double(v.startLocation.y / px)
                    // Grab the nearer marker and keep its offset from the finger, so it doesn't jump.
                    dragging = abs(startMM - a) <= abs(startMM - b) ? .a : .b
                    dragStartMM = dragging == .a ? a : b
                }
                let target = clampMM(snap(dragStartMM + Double(v.translation.height / px)), maxMM: maxMM)
                let old = dragging == .a ? a : b
                if dragging == .a { a = target } else { b = target }
                // A light tick on each whole centimetre (or inch) crossed, never per frame.
                let major = unit == .inch ? 25.4 : 10
                if Int((old / major).rounded(.down)) != Int((target / major).rounded(.down)) { Haptics.selection() }
            }
            .onEnded { v in
                defer { dragging = nil }
                guard !locked, dragging == nil, px > 0 else { return }
                // Tap: place A, then B.
                let mm = clampMM(snap(Double(v.location.y / px)), maxMM: maxMM)
                if nextTap == .a { a = mm; nextTap = .b } else { b = mm; nextTap = .a }
                Haptics.selection()
            }
    }

    private func save() {
        MeasurementStore.shared.add(MeasurementRecord(
            name: "Screen ruler", value: distanceText, source: .sensor, tool: .ruler, projectID: nil, date: Date()))
        withAnimation(PM.Motion.normal) { showToast = true }
    }
}

// MARK: - Strip

private struct RulerStrip: View {
    var unit: RulerView.Unit
    var px: CGFloat
    var maxMM: Double
    var a: Double
    var b: Double

    private static let stripLeft = Color(dark: 0x1A2024, light: 0xFFFFFF)
    private static let stripRight = Color(dark: 0x14191C, light: 0xF6F5F1)
    private static let edge = Color(dark: 0x2E363C, light: 0xD6D9D4)
    private static let whole = Color(dark: 0xE3E8EA, light: 0x0E1113)
    private static let five = Color(dark: 0x8A959B, light: 0x545D63)
    private static let minor = Color(dark: 0x4A555C, light: 0x9AA39E)
    private static let eighth = Color(dark: 0x6E7A81, light: 0x545D63)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Self.stripLeft, Self.stripRight], startPoint: .leading, endPoint: .trailing)
            Rectangle().fill(Self.edge).frame(width: 1).frame(maxWidth: .infinity, alignment: .trailing)

            // A → B band
            Rectangle()
                .fill(PM.Colors.accent.opacity(0.08))
                .frame(width: 96, height: max(0, CGFloat(abs(b - a)) * px))
                .offset(y: CGFloat(min(a, b)) * px)

            Canvas { ctx, _ in
                if unit == .inch {
                    let step = 25.4 / 16
                    var i = 0
                    while Double(i) * step <= maxMM {
                        let w: CGFloat = i % 16 == 0 ? 40 : i % 8 == 0 ? 28 : i % 4 == 0 ? 20 : i % 2 == 0 ? 12 : 8
                        let y = 1 + CGFloat(Double(i) * step) * px
                        ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: 1)),
                                 with: .color(i % 16 == 0 ? Self.whole : i % 2 == 0 ? Self.eighth : Self.minor))
                        i += 1
                    }
                } else {
                    for m in 0...Int(maxMM) {
                        let w: CGFloat = m % 10 == 0 ? 40 : m % 5 == 0 ? 26 : 14
                        let color = m % 10 == 0 ? Self.whole : m % 5 == 0 ? Self.five : Self.minor
                        ctx.fill(Path(CGRect(x: 0, y: 1 + CGFloat(m) * px, width: w, height: 1)), with: .color(color))
                    }
                }
            }

            ForEach(labels, id: \.self) { l in
                Text(l.text)
                    .font(.pmMono(14))
                    .foregroundStyle(PM.Colors.textPrimary)
                    .fixedSize()
                    .offset(x: 46, y: 1 + l.y - 8.5)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private struct RulerLabel: Hashable { var text: String; var y: CGFloat }

    private var labels: [RulerLabel] {
        var out: [RulerLabel] = []
        if unit == .inch {
            var i = 1
            while Double(i) * 25.4 <= maxMM {
                out.append(RulerLabel(text: "\(i)", y: CGFloat(Double(i) * 25.4) * px))
                i += 1
            }
        } else if maxMM >= 10 {
            for m in stride(from: 10, through: Int(maxMM), by: 10) {
                out.append(RulerLabel(text: unit == .mm ? "\(m)" : "\(m / 10)", y: CGFloat(m) * px))
            }
        }
        return out
    }
}

/// A (full-width lavender line) and B (140 pt accent line) with their chips at x 104.
private struct RulerMarkers: View {
    var px: CGFloat
    var a: Double
    var b: Double
    var width: CGFloat

    var body: some View {
        let ay = CGFloat(a) * px
        let by = 1 + CGFloat(b) * px
        ZStack(alignment: .topLeading) {
            Rectangle().fill(PM.Colors.calibrating)
                .frame(width: width, height: 2)
                .offset(y: ay)
            RulerChip(text: "A", fill: PM.Colors.calibrating, ink: PM.Colors.onThumb)
                .offset(x: 104, y: ay - 10)

            Rectangle().fill(PM.Colors.accent)
                .frame(width: 140, height: 2)
                .shadow(color: PM.Colors.accent.opacity(0.6), radius: 5)
                .offset(y: by - 1)
            RulerChip(text: "B", fill: PM.Colors.accent, ink: PM.Colors.onAccent)
                .offset(x: 104, y: by - 11)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private struct RulerChip: View {
    var text: String
    var fill: Color
    var ink: Color

    var body: some View {
        Text(text)
            .font(.pm(12, .heavy))
            .foregroundStyle(ink)
            .frame(width: 24, height: 22)
            .background(Capsule().fill(fill))
    }
}

/// − 1 mm / + 1 mm: 48 tall secondary pill, 16 bold.
private struct RulerStepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(16, .bold))
            .foregroundStyle(PM.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Capsule().fill(PM.Colors.surfaceRaised))
            .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - Calibration

/// Card calibration: match the short edge of an ID-1 card (ISO/IEC 7810, 85.60 × 53.98 mm).
private struct RulerCalibrationSheet: View {
    @Binding var calibratedPtPerMM: Double
    var modelScale: RulerScreenScale?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var value: Double = 6

    private static let cardShortMM = 53.98
    private static let cardLongMM = 85.60
    private var range: ClosedRange<Double> { 3...12 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Screen scale") { dismiss() }
            Text("Hold a bank card or ID card flat against the screen, its top-left corner in the outline's corner. Adjust until the card's short edge matches the outline exactly.")
                .font(.pm(15))
                .foregroundStyle(PM.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { g in
                let w = CGFloat(Self.cardShortMM * value)
                let h = CGFloat(Self.cardLongMM * value)
                RoundedRectangle(cornerRadius: CGFloat(3.18 * value), style: .continuous)
                    .strokeBorder(PM.Colors.accent, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: CGFloat(3.18 * value), style: .continuous)
                        .fill(PM.Colors.accent.opacity(0.06)))
                    .frame(width: w, height: h)
                    .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                    .offset(x: -20) // flush with the screen's left edge
                    .accessibilityHidden(true)
            }
            .frame(height: 230)
            .clipped()

            HStack(spacing: 10) {
                Button { value = max(range.lowerBound, value - 0.01) } label: { PMIcon(.minus, size: 18, stroke: 2) }
                    .buttonStyle(PMSecondaryButtonStyle(height: 44, horizontalPadding: 14))
                    .accessibilityLabel("Smaller")
                Slider(value: $value, in: range)
                    .accessibilityLabel("Card outline size")
                    .accessibilityValue(String(format: "%.2f points per millimetre", value))
                Button { value = min(range.upperBound, value + 0.01) } label: { PMIcon(.plus, size: 18, stroke: 2) }
                    .buttonStyle(PMSecondaryButtonStyle(height: 44, horizontalPadding: 14))
                    .accessibilityLabel("Larger")
            }

            HStack(spacing: 10) {
                if modelScale != nil {
                    Button("Use model default") {
                        calibratedPtPerMM = 0
                        Haptics.selection()
                        dismiss()
                    }
                    .buttonStyle(PMSecondaryButtonStyle(fillWidth: true))
                }
                Button("Save") {
                    calibratedPtPerMM = value
                    Haptics.calibrationComplete()
                    dismiss()
                }
                .buttonStyle(.pmPrimary)
            }
        }
        .padding(20)
        .background(PM.Colors.background.ignoresSafeArea())
        .onAppear {
            value = RulerScreenScale.resolve(calibrated: calibratedPtPerMM, fallbackScale: displayScale).pointsPerMM
                .clamped(to: range)
        }
    }
}

private extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double { Swift.min(r.upperBound, Swift.max(r.lowerBound, self)) }
}

private extension CGFloat {
    func clamped(to r: ClosedRange<Double>) -> Double { Double(self).clamped(to: r) }
}

// MARK: - Screen scale

/// Physical screen density. Points per millimetre = ppi ÷ native scale ÷ 25.4.
/// PPI values are Apple's published "pixels per inch" for each model.
struct RulerScreenScale {
    var modelName: String
    var pointsPerMM: CGFloat
    /// False when the model is unknown and the user hasn't calibrated: the ruler is then only approximate.
    var isTrusted: Bool

    static let calibrationKey = "ruler.calibratedPtPerMM"

    /// The scale from the model table, if this device is in it.
    static var modelScale: RulerScreenScale? {
        let id = modelIdentifier
        guard let (name, ppi) = table[id] ?? iPadScale(id) else { return nil }
        let native = currentNativeScale
        guard native > 0 else { return nil }
        return RulerScreenScale(modelName: name, pointsPerMM: CGFloat(ppi) / native / 25.4, isTrusted: true)
    }

    /// A saved calibration wins; then the model table; then an approximate default (flagged untrusted).
    static func resolve(calibrated: Double, fallbackScale: CGFloat) -> RulerScreenScale {
        if calibrated.isFinite, calibrated > 1 {
            return RulerScreenScale(modelName: "Calibrated", pointsPerMM: CGFloat(calibrated), isTrusted: true)
        }
        if let model = modelScale { return model }
        // Typical modern iPhone density (460 ppi at 3x) as a starting point.
        let native = currentNativeScale > 0 ? currentNativeScale : (fallbackScale > 0 ? fallbackScale : 3)
        return RulerScreenScale(modelName: "This device", pointsPerMM: 460 / native / 25.4, isTrusted: false)
    }

    /// Native scale of the screen showing the app, from the window scene (UIScreen.main is deprecated).
    /// nativeScale, not scale, so Display Zoom is accounted for.
    private static var currentNativeScale: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.nativeScale ?? 0
    }

    private static var modelIdentifier: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// iPads: Apple publishes 326 ppi for iPad mini and 264 ppi for every other current iPad
    /// (iPad, iPad Air, iPad Pro 11" and 13"). Matched by identifier so new models are covered.
    private static func iPadScale(_ id: String) -> (String, Int)? {
        guard id.hasPrefix("iPad") else { return nil }
        let miniIDs: Set<String> = ["iPad11,1", "iPad11,2", "iPad14,1", "iPad14,2", "iPad16,1", "iPad16,2"]
        return miniIDs.contains(id) ? ("iPad mini", 326) : ("iPad", 264)
    }

    /// Model identifier → (marketing name, pixels per inch). iPhone models that run iOS 26.
    private static let table: [String: (String, Int)] = [
        "iPhone12,1": ("iPhone 11", 326), "iPhone12,3": ("iPhone 11 Pro", 458), "iPhone12,5": ("iPhone 11 Pro Max", 458),
        "iPhone12,8": ("iPhone SE", 326),
        "iPhone13,1": ("iPhone 12 mini", 476), "iPhone13,2": ("iPhone 12", 460),
        "iPhone13,3": ("iPhone 12 Pro", 460), "iPhone13,4": ("iPhone 12 Pro Max", 458),
        "iPhone14,4": ("iPhone 13 mini", 476), "iPhone14,5": ("iPhone 13", 460),
        "iPhone14,2": ("iPhone 13 Pro", 460), "iPhone14,3": ("iPhone 13 Pro Max", 458),
        "iPhone14,6": ("iPhone SE", 326),
        "iPhone14,7": ("iPhone 14", 460), "iPhone14,8": ("iPhone 14 Plus", 458),
        "iPhone15,2": ("iPhone 14 Pro", 460), "iPhone15,3": ("iPhone 14 Pro Max", 460),
        "iPhone15,4": ("iPhone 15", 460), "iPhone15,5": ("iPhone 15 Plus", 460),
        "iPhone16,1": ("iPhone 15 Pro", 460), "iPhone16,2": ("iPhone 15 Pro Max", 460),
        "iPhone17,3": ("iPhone 16", 460), "iPhone17,4": ("iPhone 16 Plus", 460),
        "iPhone17,1": ("iPhone 16 Pro", 460), "iPhone17,2": ("iPhone 16 Pro Max", 460),
        "iPhone17,5": ("iPhone 16e", 460),
        "iPhone18,3": ("iPhone 17", 460), "iPhone18,4": ("iPhone Air", 460),
        "iPhone18,1": ("iPhone 17 Pro", 460), "iPhone18,2": ("iPhone 17 Pro Max", 460),
        "iPhone18,5": ("iPhone 17e", 460),
    ]
}
