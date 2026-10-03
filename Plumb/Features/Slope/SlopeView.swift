//
//  SlopeView.swift
//  Plumb
//
//  Slope / Grade calculator (Slope board). Rise and run are user-entered; slope, angle and ratio are calculated.
//  Any result can also be typed in (tap it): the rise is then worked back from the run.
//

import SwiftUI

struct SlopeView: View {
    @Environment(Router.self) private var router
    @Environment(MeasurementStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @AppStorage("slope.rise") private var riseText = "12"
    @AppStorage("slope.run") private var runText = "240"
    @FocusState private var focused: Field?

    @State private var inverse: SlopeMath.Inverse?
    @State private var inverseText = ""
    @State private var inverseError: String?
    @State private var toast: String?

    private enum Field { case rise, run }

    private var rise: Double? { SlopeMath.parse(riseText) }
    private var run: Double? { SlopeMath.parse(runText) }
    private var ok: Bool { (rise ?? 0) > 0 && (run ?? 0) > 0 }
    private var degrees: Double { ok ? atan(rise! / run!) * 180 / .pi : 0 }

    private var unitLabel: String { settings.units == .imperial ? "in" : "cm" }
    private var pctText: String { ok ? SlopeMath.format(rise! / run! * 100, decimals: 1) + "%" : "—" }
    private var degText: String { ok ? SlopeMath.format(degrees, decimals: 1) + "°" : "—" }
    private var ratioText: String {
        guard ok else { return "—" }
        let r = run! / rise!
        return "1 : " + (r >= 10 ? SlopeMath.format(r.rounded(), decimals: 0) : SlopeMath.format(r, decimals: 1))
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            SlopeDiagram(degrees: degrees, riseText: displayInput(riseText), runText: displayInput(runText),
                         degText: degText, unit: unitLabel)
            HStack(alignment: .top, spacing: 12) {
                inputCard(label: "RISE", text: $riseText, field: .rise, step: 1)
                inputCard(label: "RUN", text: $runText, field: .run, step: 10)
            }
            result
            Spacer(minLength: 0)
            Button("Save to project", action: save)
                .buttonStyle(.pmPrimary)
                .disabled(!ok)
                .opacity(ok ? 1 : 0.5)
        }
        .padding(.top, 56 - PM.Board.statusBar)
        .padding(.horizontal, 20)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PM.Colors.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let toast {
                ToastView(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .alert(inverse?.title ?? "", isPresented: Binding(get: { inverse != nil }, set: { if !$0 { inverse = nil } })) {
            TextField(inverse?.placeholder ?? "", text: $inverseText)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { inverse = nil }
            Button("Apply") { applyInverse() }
        } message: {
            Text(inverse?.message(run: displayInput(runText), unit: unitLabel) ?? "")
        }
        .onChange(of: riseText) { _, new in
            let clean = SlopeMath.sanitize(new)
            if clean != new { riseText = clean }
        }
        .onChange(of: runText) { _, new in
            let clean = SlopeMath.sanitize(new)
            if clean != new { runText = clean }
        }
    }

    // MARK: Sections

    private var header: some View {
        ZStack {
            Text("Slope / Grade")
                .font(.pm(17, .semibold))
                .foregroundStyle(PM.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                IconCircleButton(icon: .back, label: "Back to tools", stroke: 2) { router.pop() }
                Spacer()
                TopBarPlaceholder()
            }
        }
    }

    private func inputCard(label: String, text: Binding<String>, field: Field, step: Double) -> some View {
        let value = SlopeMath.parse(text.wrappedValue)
        let invalid = (value ?? 0) <= 0
        return VStack(alignment: .leading, spacing: 8) {
            Text(label).pmCaptionStyle(tracking: 1.2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .focused($focused, equals: field)
                    .font(.pm(30, .medium))
                    .monospacedDigit()
                    .foregroundStyle(PM.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel(label == "RISE" ? "Rise" : "Run")
                    .accessibilityValue("\(text.wrappedValue) \(unitLabel == "cm" ? "centimetres" : "inches")")
                Text(unitLabel).font(.pm(15)).foregroundStyle(PM.Colors.textSecondary)
            }
            HStack(spacing: 8) {
                stepButton("−", label: "Decrease \(label.lowercased())") {
                    text.wrappedValue = SlopeMath.clampText((value ?? 0) - step)
                }
                stepButton("+", label: "Increase \(label.lowercased())") {
                    text.wrappedValue = SlopeMath.clampText((value ?? 0) + step)
                }
            }
            Text(invalid ? "Enter a number above 0" : "User-entered")
                .font(.pm(12, .semibold))
                .foregroundStyle(invalid ? PM.Colors.warning : PM.Colors.calibrating)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmCard(border: invalid ? PM.Colors.warning.opacity(0.6) : PM.Colors.border)
    }

    private func stepButton(_ glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.pm(20))
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(PM.Colors.surfaceRaised))
                .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pmPress)
        .accessibilityLabel(label)
        .buttonRepeatBehavior(.enabled)
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RESULT").pmCaptionStyle(tracking: 1.2)
                Spacer()
                Text("Calculated").font(.pm(12, .semibold)).foregroundStyle(PM.Colors.measuring)
            }
            HStack(alignment: .top, spacing: 8) {
                resultCell(value: pctText, label: "Slope", accent: true, kind: .percent)
                resultCell(value: degText, label: "Angle", accent: false, kind: .degrees)
                resultCell(value: ratioText, label: "Ratio", accent: false, kind: .ratio)
            }
            PM.Colors.border.frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Slope % = Rise ÷ Run × 100 = \(displayInput(riseText)) ÷ \(displayInput(runText)) × 100")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .cssLineBox(fontSize: 13, lineHeight: 1.5)
                Text("Angle = arctan(Rise ÷ Run)").cssLineBox(fontSize: 13, lineHeight: 1.5)
                Text("Ratio = 1 : (Run ÷ Rise), rounded").cssLineBox(fontSize: 13, lineHeight: 1.5)
            }
            .font(.pm(13))
            .monospacedDigit()
            .foregroundStyle(PM.Colors.textSecondary)
        }
        .padding(16)
        .pmCard(fill: PM.Colors.surfaceSunken)
    }

    private func resultCell(value: String, label: String, accent: Bool, kind: SlopeMath.Inverse) -> some View {
        Button {
            inverseText = ""
            inverse = kind
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.pm(30, .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(accent ? PM.Colors.accent : PM.Colors.textPrimary)
                Text(label).font(.pm(12)).foregroundStyle(PM.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pmPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-tap to enter a \(label.lowercased()) and work out the rise")
    }

    // MARK: Actions

    private func displayInput(_ s: String) -> String { s.isEmpty ? "0" : s }

    private func applyInverse() {
        guard let kind = inverse else { return }
        inverse = nil
        guard let runValue = run, runValue > 0 else {
            flash("Enter a run first")
            return
        }
        switch kind.rise(fromInput: inverseText, run: runValue) {
        case .success(let r): riseText = SlopeMath.clampText(r, decimals: 2)
        case .failure(let e): flash(e.message)
        }
    }

    private func flash(_ text: String) {
        withAnimation(PM.Motion.normal) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(PM.Motion.normal) { toast = nil }
        }
    }

    private func save() {
        guard ok else { return }
        let project = store.projects.first
        store.add(MeasurementRecord(
            name: "Slope",
            value: "\(pctText) · \(degText)",
            source: .calculated,
            tool: .slope,
            projectID: project?.id,
            date: Date()
        ))
        if project != nil { router.select(.projects) } else { flash("Saved to History") }
    }
}

// MARK: - Diagram

/// Rise/run triangle. The line is drawn four times steeper (max 40°) so shallow grades stay readable.
private struct SlopeDiagram: View {
    var degrees: Double
    var riseText: String
    var runText: String
    var degText: String
    var unit: String

    private let height: CGFloat = 176

    var body: some View {
        let vis = min(40, degrees * 4)
        let rad = vis * .pi / 180
        // Keep the triangle clear of the top captions at steep angles.
        let len: CGFloat = rad > 0 ? min(300, 92 / sin(rad)) : 300
        let h = sin(rad) * len
        let w = cos(rad) * len
        let baseY = height - 40
        // Angle label: inside the wedge near the vertex when it fits, otherwise just above the line.
        let tanV = tan(rad)
        let lx: CGFloat = 88, dx = lx - 24
        let inside = dx * tanV >= 16 + 8
        let labelBottom = inside ? 44 : 40.5 + (dx + 40) * tanV + 4

        ZStack(alignment: .topLeading) {
            // 20 pt grid
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = 0
                while x <= size.width { p.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 20 }
                var y: CGFloat = 0
                while y <= size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 20 }
                ctx.fill(p, with: .color(PM.Colors.textPrimary.opacity(0.03)))
            }

            // Baseline
            PM.Colors.tickMinor
                .frame(width: 302, height: 1)
                .offset(x: 24, y: baseY - 1)

            // Slope line, rotated about its left end
            Capsule()
                .fill(PM.Colors.accent)
                .frame(width: len, height: 2)
                .shadow(color: PM.Colors.accent.opacity(0.4), radius: 6)
                .rotationEffect(.degrees(-vis), anchor: .leading)
                .offset(x: 24, y: baseY - 1.5)

            // Rise, dashed
            Path { p in
                p.move(to: CGPoint(x: 24 + w, y: baseY - 0.5))
                p.addLine(to: CGPoint(x: 24 + w, y: baseY - 0.5 - max(0, h)))
            }
            .stroke(PM.Colors.unavailable, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            Circle()
                .fill(PM.Colors.accent)
                .frame(width: 10, height: 10)
                .offset(x: 19, y: height - 35.5 - 10)

            Text("Run \(runText) \(unit)")
                .font(.pm(12)).monospacedDigit()
                .foregroundStyle(PM.Colors.textSecondary)
                .lineLimit(1)
                .offset(x: 24, y: height - 12 - 14.5)

            Text(degText)
                .font(.pm(13, .semibold)).monospacedDigit()
                .foregroundStyle(PM.Colors.accent)
                .fixedSize()
                .offset(x: lx, y: height - labelBottom - 15.5)

            Text("Angle drawn steeper to be readable")
                .font(.pm(12, .semibold))
                .foregroundStyle(PM.Colors.textTertiary)
                .offset(x: 16, y: 14)

            Text("Rise \(riseText) \(unit)")
                .font(.pm(12)).monospacedDigit()
                .foregroundStyle(PM.Colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                .offset(y: 14)
        }
        .animation(PM.Motion.spatial(0.3), value: vis)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: PM.Radius.card, style: .continuous))
        .pmCard(fill: PM.Colors.surfaceSunken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slope diagram, rise \(riseText) over run \(runText) \(unit), \(degText)")
    }
}

// MARK: - Maths

private enum SlopeMath {
    static let maxValue = 1_000_000.0

    /// Accepts "12", "12.5" and "12,5". Anything else (empty, "-", "1.2.3", NaN) is nil.
    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return min(v, maxValue)
    }

    /// Keeps digits and a single decimal separator, at most 7 integer and 3 decimal digits.
    static func sanitize(_ s: String) -> String {
        var out = ""
        var seenSep = false
        var intDigits = 0, fracDigits = 0
        for ch in s {
            if ch.isASCII, ch.isNumber {
                if seenSep { guard fracDigits < 3 else { continue }; fracDigits += 1 }
                else { guard intDigits < 7 else { continue }; intDigits += 1 }
                out.append(ch)
            } else if (ch == "." || ch == ","), !seenSep {
                seenSep = true
                out.append(ch)
            }
        }
        return out
    }

    /// Rounds and never goes below zero, like the board's stepper.
    static func clampText(_ v: Double, decimals: Int = 1) -> String {
        guard v.isFinite else { return "0" }
        let f = pow(10, Double(decimals))
        let r = min(maxValue, max(0, (v * f).rounded() / f))
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.\(decimals)f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    static func format(_ v: Double, decimals: Int) -> String {
        guard v.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", v)
    }

    enum InputError: Error {
        case notANumber, outOfRange(String)
        var message: String {
            switch self {
            case .notANumber: "Enter a number"
            case .outOfRange(let s): s
            }
        }
    }

    /// Typing a result in: slope %, angle in degrees, or the n of a 1 : n ratio.
    enum Inverse: Identifiable {
        case percent, degrees, ratio
        var id: Self { self }

        var title: String {
            switch self {
            case .percent: "Enter slope %"
            case .degrees: "Enter angle"
            case .ratio: "Enter ratio 1 : n"
            }
        }

        var placeholder: String {
            switch self {
            case .percent: "Slope in %"
            case .degrees: "Angle in degrees"
            case .ratio: "n, as in 1 : n"
            }
        }

        func message(run: String, unit: String) -> String {
            "The rise is worked out for the current run of \(run) \(unit)."
        }

        func rise(fromInput s: String, run: Double) -> Result<Double, InputError> {
            let raw = s.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "°", with: "")
                .replacingOccurrences(of: "1:", with: "").replacingOccurrences(of: "1 :", with: "")
            guard let v = SlopeMath.parse(raw) else { return .failure(.notANumber) }
            switch self {
            case .percent:
                guard v > 0, v <= 10_000 else { return .failure(.outOfRange("Slope must be above 0% and at most 10,000%")) }
                return .success(run * v / 100)
            case .degrees:
                guard v > 0, v < 90 else { return .failure(.outOfRange("Angle must be between 0° and 90°")) }
                return .success(run * tan(v * .pi / 180))
            case .ratio:
                guard v > 0 else { return .failure(.outOfRange("n must be above 0")) }
                return .success(run / v)
            }
        }
    }
}
