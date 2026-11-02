//
//  ShapeCalculatorView.swift
//  Plumb
//
//  One shape's calculator: proportional diagram, inputs in one shared unit, live area and perimeter
//  in any output unit, and the formula with the entered numbers substituted.
//

import SwiftUI
import UIKit

struct ShapeCalculatorView: View {
    let kind: ShapeKind

    @Environment(Router.self) private var router
    @Environment(MeasurementStore.self) private var store

    @State private var measure: CircleMeasure
    @State private var texts: [String: String]
    @State private var inputUnit: ShapeLengthUnit
    @AppStorage("shapes.areaUnit") private var areaUnitRaw = ""
    @FocusState private var focused: String?

    @State private var toast: String?
    @State private var choosingProject = false
    @State private var naming = false
    @State private var newProjectName = ""
    @State private var screenHeight: CGFloat = 800

    init(kind: ShapeKind) {
        self.kind = kind
        let saved = ShapeMemory.load(kind)
        let measure = saved?.measure ?? .radius
        _measure = State(initialValue: measure)
        var t: [String: String] = [:]
        for i in kind.inputs(measure) { t[i.symbol] = saved?.values[i.symbol] ?? i.defaultValue }
        _texts = State(initialValue: t)
        _inputUnit = State(initialValue: saved?.unit ?? (AppSettings.shared.units == .imperial ? .ft : .m))
    }

    // MARK: Derived

    private var inputs: [ShapeInput] { kind.inputs(measure) }

    private var areaUnit: ShapeAreaUnit {
        ShapeAreaUnit(rawValue: areaUnitRaw) ?? ShapeAreaUnit.matching(inputUnit)
    }

    private func text(_ symbol: String) -> String { texts[symbol] ?? "" }

    /// Parsed inputs: lengths in metres, angles in degrees, counts as numbers. Empty fields are absent.
    private var parsed: [String: Double] {
        var out: [String: Double] = [:]
        for i in inputs {
            let raw = text(i.symbol).trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            guard let v = ShapeNumber.parse(raw) else { out[i.symbol] = .nan; continue }
            out[i.symbol] = i.kind == .length ? v * inputUnit.metres : v
        }
        return out
    }

    /// Entered values in their own units, for drawing.
    private var rawValues: [String: Double] {
        var out: [String: Double] = [:]
        for i in inputs { if let v = ShapeNumber.parse(text(i.symbol)) { out[i.symbol] = v } }
        return out
    }

    private var outcome: Result<ShapeResult, ShapeError> { kind.compute(parsed, measure: measure) }

    private var result: ShapeResult? {
        if case .success(let r) = outcome { return r }
        return nil
    }

    private var errorMessage: String? {
        if case .failure(let e) = outcome { return e.message }
        return nil
    }

    private var areaText: String { result.map { ShapeNumber.format($0.area / areaUnit.squareMetres) } ?? "—" }

    private var perimeterText: String {
        guard let p = result?.perimeter else { return "—" }
        return ShapeNumber.format(p / areaUnit.perimeterUnit.metres)
    }

    private var perimeterName: String {
        switch kind {
        case .circle: "Circumference"
        case .ring: "Total edge length"
        default: "Perimeter"
        }
    }

    private func unitLabel(_ i: ShapeInput) -> String {
        switch i.kind {
        case .length: inputUnit.symbol
        case .angle: "°"
        case .count: "sides"
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if focused != nil {
                pinnedWhileTyping
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            scrollArea
        }
        .padding(.top, 56 + 1 - PM.Board.statusBar)
        .background(PM.Colors.background.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            if focused == nil { screenHeight = h }
        }
        .animation(PM.Motion.normal, value: focused == nil)
        .overlay(alignment: .bottom) {
            if let toast {
                ToastView(text: toast)
                    .padding(.bottom, 96)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Previous") { step(-1) }
                    .disabled(index(of: focused) == 0)
                Button("Next") { step(1) }
                    .disabled(index(of: focused) >= inputs.count - 1)
                Spacer()
                Button("Done") { focused = nil }.bold()
            }
        }
        .confirmationDialog("Save \(areaText) \(areaUnit.symbol)", isPresented: $choosingProject, titleVisibility: .visible) {
            ForEach(store.projects) { p in
                Button(p.name) { save(to: p.id) }
            }
            Button("New project\u{2026}") {
                newProjectName = ""
                naming = true
            }
            Button("History only") { save(to: nil) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New project", isPresented: $naming) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) {}
            Button("Create and save") {
                guard MeasurementStore.cleanName(newProjectName) != nil else { return }
                let p = store.addProject(named: newProjectName)
                save(to: p.id)
            }
        } message: {
            Text("Name the real-world job, for example \u{201C}Back deck\u{201D}.")
        }
        .onChange(of: texts) { _, new in ShapeMemory.save(kind, values: new, unit: inputUnit, measure: measure) }
        .onChange(of: inputUnit) { _, new in ShapeMemory.save(kind, values: texts, unit: new, measure: measure) }
        .onChange(of: measure) { _, new in ShapeMemory.save(kind, values: texts, unit: inputUnit, measure: new) }
    }

    // MARK: Sections

    private var scrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Diagram, then the answer, both above the fold on every phone. While typing they
                    // are replaced by the pinned strip above the scroll view.
                    if focused == nil {
                        diagramCard(height: diagramHeight)
                        resultCard
                    }
                    if kind.usesCircleMeasure {
                        PMSegmented(options: [(CircleMeasure.radius, "Radius"), (CircleMeasure.diameter, "Diameter")],
                                    selection: Binding(get: { measure }, set: switchMeasure),
                                    segmentHeight: 44, fontSize: 14, fontWeight: .bold, tracking: 0, trackPadding: 5)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Enter by")
                    }
                    inputsCard
                    detailsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // The action bar is a bottom inset, so the last formula line always scrolls clear of it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focused == nil {
                    actionBar
                        .background(PM.Colors.background)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: focused) { _, f in
                guard let f else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(PM.Motion.normal) { proxy.scrollTo("field.\(f)", anchor: .center) }
                }
            }
        }
    }

    /// Shown while the keyboard is up: the answer, plus a compact diagram on phones tall enough for it.
    private var pinnedWhileTyping: some View {
        VStack(spacing: 8) {
            if screenHeight >= 740 {
                diagramCard(height: 124)
            }
            typingStrip
        }
    }

    private var topBar: some View {
        PMTopBar(title: kind.name, topPadding: 0, horizontalPadding: 20, leading: {
            IconCircleButton(icon: .back, label: "Back to shapes", stroke: 2) { router.pop() }
        }) {
            ShareLink(item: shareText, subject: Text("\(kind.name) area"), preview: SharePreview("\(kind.name) area")) {
                PMIcon(.share, size: 20, stroke: 1.8)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(PM.Colors.surface))
                    .overlay(Circle().strokeBorder(PM.Colors.border, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.pmPress)
            .disabled(result == nil)
            .opacity(result == nil ? 0.5 : 1)
            .accessibilityLabel("Share result")
        }
    }

    /// 150 on the iPhone SE (647 pt between the safe areas) up to 232 from 844 pt phones (755 pt and taller).
    private var diagramHeight: CGFloat {
        let fit = min(1, max(0, (screenHeight - 647) / (755 - 647)))
        return (150 + (232 - 150) * fit).rounded()
    }

    private func diagramCard(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = 0
                while x <= size.width { p.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 20 }
                var y: CGFloat = 0
                while y <= size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 20 }
                ctx.fill(p, with: .color(PM.Colors.textPrimary.opacity(0.03)))
            }
            // Room for the dimension chips scales with the card: 26 pt at 124, 30 at 150, 44 at 232.
            let roomy = height >= 170
            ShapeDiagramView(kind: kind, measure: measure, values: rawValues, labelText: diagramLabel, lineWidth: 2.2,
                             inset: max(26, min(44, (height - 14) * 0.2)))
                .padding(.top, roomy ? 14 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.78), value: rawValues)
                .animation(.spring(response: 0.45, dampingFraction: 0.78), value: measure)
            // The caption needs the top band of a full-size card; compact cards drop it.
            if roomy {
                Text(errorMessage == nil || result != nil ? "Proportions follow your values" : "Check the values below")
                    .font(.pm(12, .semibold))
                    .foregroundStyle(result == nil && errorMessage != nil ? PM.Colors.warning : PM.Colors.textTertiary)
                    .padding(.leading, 16)
                    .padding(.top, 12)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: PM.Radius.card, style: .continuous))
        .pmCard(fill: PM.Colors.surfaceSunken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(diagramAccessibility)
    }

    private var inputsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("UNITS").pmCaptionStyle(tracking: 1.2)
                Spacer()
                Text("User-entered").font(.pm(12, .semibold)).foregroundStyle(PM.Colors.calibrating)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            ChipRow(items: ShapeLengthUnit.allCases, selected: inputUnit, label: \.symbol, spoken: \.spoken) { u in
                setInputUnit(u)
            }
            .accessibilityLabel("Input unit")
            .padding(.top, 4)
            .padding(.bottom, 6)

            ForEach(inputs) { i in
                PM.Colors.border.frame(height: 1)
                inputRow(i)
            }
        }
        .pmCard()
    }

    private func inputRow(_ i: ShapeInput) -> some View {
        let error = fieldError(i)
        let empty = text(i.symbol).trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 12) {
            Text(i.symbol)
                .font(.pm(16, .bold))
                .foregroundStyle(PM.Colors.accent)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: PM.Radius.iconWell, style: .continuous).fill(PM.Colors.iconWell))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.name).font(.pm(15, .semibold)).foregroundStyle(PM.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(error ?? (i.optional && empty ? "Optional" : "User-entered"))
                    .font(.pm(12, .semibold))
                    .foregroundStyle(error != nil ? PM.Colors.warning : i.optional && empty ? PM.Colors.textTertiary : PM.Colors.calibrating)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            TextField(i.optional ? "—" : "0", text: Binding(
                get: { text(i.symbol) },
                set: { texts[i.symbol] = i.kind == .count ? ShapeNumber.sanitize($0).filter(\.isNumber) : ShapeNumber.sanitize($0) }
            ))
                .keyboardType(i.kind == .count ? .numberPad : .decimalPad)
                .focused($focused, equals: i.symbol)
                .multilineTextAlignment(.trailing)
                .font(.pm(20))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
                .frame(width: 112, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PM.Colors.surfaceRaised))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(error != nil ? PM.Colors.warning : focused == i.symbol ? PM.Colors.accent : PM.Colors.borderStrong,
                                  lineWidth: 1))
                .accessibilityLabel("\(i.name) \(i.symbol), \(spokenUnit(i))\(i.optional ? ", optional" : "")")
                .accessibilityHint(error ?? "")
            Text(unitLabel(i))
                .font(.pm(15))
                .foregroundStyle(PM.Colors.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 26, alignment: .leading)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { focused = i.symbol }
        .id("field.\(i.symbol)")
    }

    private var areaValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(areaText)
                .font(.pm(44, .light))
                .tracking(-1)
                .monospacedDigit()
                .foregroundStyle(result == nil ? PM.Colors.textTertiary : PM.Colors.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
            Text(areaUnit.symbol)
                .font(.pm(20))
                .foregroundStyle(PM.Colors.textSecondary)
                .fixedSize()
        }
    }

    private var perimeterValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text((result?.perimeterIsApproximate == true && result?.perimeter != nil ? "≈ " : "") + perimeterText)
                .font(.pm(22, .regular))
                .monospacedDigit()
                .foregroundStyle(result?.perimeter == nil ? PM.Colors.textTertiary : PM.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if result?.perimeter != nil {
                Text(areaUnit.perimeterUnit.symbol)
                    .font(.pm(15))
                    .foregroundStyle(PM.Colors.textSecondary)
                    .fixedSize()
            }
        }
    }

    /// The answer: area, perimeter and the output unit, right under the diagram.
    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RESULT").pmCaptionStyle(tracking: 1.4)
                Spacer()
                Text("Calculated").font(.pm(12, .semibold)).foregroundStyle(PM.Colors.measuring)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Area").font(.pm(13, .semibold)).foregroundStyle(PM.Colors.textSecondary)
                areaValue
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(result == nil ? "Area, no result yet" : "Area, \(areaText) \(areaUnit.spoken)")

            HStack(alignment: .firstTextBaseline) {
                Text(perimeterName).font(.pm(13, .semibold)).foregroundStyle(PM.Colors.textSecondary)
                Spacer(minLength: 12)
                perimeterValue
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(perimeterAccessibility)

            ForEach(problems, id: \.self) { message in
                HStack(alignment: .top, spacing: 8) {
                    PMIcon(.warning, size: 16, stroke: 2)
                    Text(message)
                        .font(.pm(13, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(PM.Colors.warning)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PM.Colors.warningFill))
                .accessibilityElement(children: .combine)
            }

            // Bleeds to the card edges so chips scroll under the padding instead of being cut at it.
            ChipRow(items: ShapeAreaUnit.allCases, selected: areaUnit, label: \.symbol, spoken: \.spoken, inset: 16) { u in
                areaUnitRaw = u.rawValue
            }
            .padding(.horizontal, -16)
            .padding(.top, -4)
            .accessibilityLabel("Show area in")
        }
        .animation(.snappy(duration: 0.25), value: areaText)
        .animation(.snappy(duration: 0.25), value: perimeterText)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmCard(radius: 24, fill: PM.Colors.surfaceSunken)
    }

    /// Pinned above the inputs while the keyboard is up, so the answer stays in view as you type.
    private var typingStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("AREA").pmCaptionStyle(tracking: 1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(areaText)
                        .font(.pm(26, .light))
                        .monospacedDigit()
                        .foregroundStyle(result == nil ? PM.Colors.textTertiary : PM.Colors.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    Text(areaUnit.symbol).font(.pm(14)).foregroundStyle(PM.Colors.textSecondary).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(result == nil ? "Area, no result yet" : "Area, \(areaText) \(areaUnit.spoken)")
            VStack(alignment: .trailing, spacing: 0) {
                Text(perimeterName.uppercased()).pmCaptionStyle(tracking: 1).lineLimit(1).minimumScaleFactor(0.7)
                perimeterValue
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(perimeterAccessibility)
        }
        .animation(.snappy(duration: 0.25), value: areaText)
        .animation(.snappy(duration: 0.25), value: perimeterText)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .pmCard(radius: 20, fill: PM.Colors.surfaceSunken)
    }

    /// Derived values, notes and the worked formula, below the inputs.
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let extras = result?.extras, !extras.isEmpty {
                Text("ALSO").pmCaptionStyle(tracking: 1)
                VStack(spacing: 6) {
                    ForEach(extras, id: \.self) { e in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(e.name) \(e.symbol)")
                                .foregroundStyle(PM.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(extraText(e))
                                .foregroundStyle(PM.Colors.textPrimary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .font(.pm(14))
                        .accessibilityElement(children: .combine)
                    }
                }
                PM.Colors.border.frame(height: 1)
            }
            if let note = result?.perimeterNote {
                Text(note)
                    .font(.pm(13))
                    .foregroundStyle(PM.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PM.Colors.border.frame(height: 1)
            }
            Text("FORMULA").pmCaptionStyle(tracking: 1)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(formulaLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.pm(13))
                        .monospacedDigit()
                        .foregroundStyle(line.hasPrefix("=") || line.hasPrefix("≈") ? PM.Colors.textPrimary : PM.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: areaText)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmCard(radius: 24, fill: PM.Colors.surfaceSunken)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Save to project") { choosingProject = true }
                .buttonStyle(.pmPrimary)
                .disabled(result == nil)
                .opacity(result == nil ? 0.5 : 1)
            Button(action: printSummary) {
                PMIcon(.printer, size: 20, stroke: 1.8)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(PM.Colors.surfaceRaised))
                    .overlay(Circle().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.pmPress)
            .disabled(result == nil)
            .opacity(result == nil ? 0.5 : 1)
            .accessibilityLabel("Print")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: Text

    /// Field messages; empty fields wait silently (the result card names the first missing value).
    private func fieldError(_ i: ShapeInput) -> String? {
        let raw = text(i.symbol).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        guard let v = ShapeNumber.parse(raw) else { return "Not a number" }
        if v <= 0 { return "Must be more than 0" }
        if i.kind == .count, v != v.rounded() { return "Whole number" }
        return nil
    }

    private var problems: [String] {
        if let errorMessage { return [errorMessage] }
        return result?.notes ?? []
    }

    private func spokenUnit(_ i: ShapeInput) -> String {
        switch i.kind {
        case .length: inputUnit.spoken
        case .angle: "degrees"
        case .count: "sides"
        }
    }

    private func extraText(_ e: ShapeExtra) -> String {
        switch e.kind {
        case .angle: ShapeNumber.format(e.value, significant: 4) + "°"
        case .length: ShapeNumber.format(e.value / areaUnit.perimeterUnit.metres) + " " + areaUnit.perimeterUnit.symbol
        }
    }

    private var perimeterAccessibility: String {
        guard let p = result?.perimeter else { return "\(perimeterName), not available. \(result?.perimeterNote ?? "")" }
        _ = p
        return "\(perimeterName), \(result?.perimeterIsApproximate == true ? "approximately " : "")\(perimeterText) \(areaUnit.perimeterUnit.spoken)"
    }

    /// "a = 4.2 m" for entered values, calculated values for derived symbols (hypotenuse c), else the symbol.
    private func diagramLabel(_ symbol: String) -> String {
        if let i = inputs.first(where: { $0.symbol == symbol }) {
            let raw = text(i.symbol).trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, ShapeNumber.parse(raw) != nil else { return symbol }
            let v = ShapeNumber.echo(raw)
            switch i.kind {
            case .length: return "\(symbol) = \(v) \(inputUnit.symbol)"
            case .angle: return "\(symbol) = \(v)°"
            case .count: return "\(symbol) = \(v)"
            }
        }
        if let e = result?.extras.first(where: { $0.symbol == symbol && $0.kind == .length }) {
            return "\(symbol) = \(ShapeNumber.format(e.value / inputUnit.metres, significant: 4)) \(inputUnit.symbol)"
        }
        return symbol
    }

    private var diagramAccessibility: String {
        let parts = inputs.compactMap { i -> String? in
            let raw = text(i.symbol)
            guard ShapeNumber.parse(raw) != nil else { return nil }
            return "\(i.name) \(i.symbol) \(ShapeNumber.echo(raw)) \(spokenUnit(i))"
        }
        return "\(kind.name) diagram" + (parts.isEmpty ? "" : ", " + parts.joined(separator: ", "))
    }

    /// Symbolic formula, then the same with the entered numbers, then the result in the chosen unit.
    private var formulaLines: [String] {
        let echo: (String) -> String = { ShapeNumber.echo(text($0)) }
        let inArea = ShapeAreaUnit.matching(inputUnit)
        var lines = [kind.areaFormula(measure)]
        guard let r = result else {
            if let p = kind.perimeterFormula(measure) { lines.append(p) }
            return lines
        }
        if kind == .triangleSides {
            let p = ((ShapeNumber.parse(text("a")) ?? 0) + (ShapeNumber.parse(text("b")) ?? 0) + (ShapeNumber.parse(text("c")) ?? 0)) / 2
            lines.append("p = (\(echo("a")) + \(echo("b")) + \(echo("c"))) ⁄ 2 = \(ShapeNumber.format(p))")
        }
        lines.append("= \(kind.areaSubstitution(measure, echo)) = \(ShapeNumber.format(r.area / inArea.squareMetres)) \(inArea.symbol)")
        if areaUnit != inArea {
            lines.append("= \(areaText) \(areaUnit.symbol)")
        }
        if let pf = kind.perimeterFormula(measure), let p = r.perimeter,
           let sub = kind.perimeterSubstitution(measure, echo) {
            lines.append(pf)
            if kind == .ellipse {
                let a = ShapeNumber.parse(text("a")) ?? 0, b = ShapeNumber.parse(text("b")) ?? 0
                lines.append("λ = ((\(echo("a")) − \(echo("b"))) ⁄ (\(echo("a")) + \(echo("b"))))² = \(ShapeNumber.format(pow((a - b) / (a + b), 2)))")
            }
            let sign = r.perimeterIsApproximate ? "≈" : "="
            lines.append("\(sign) \(sub) \(sign) \(ShapeNumber.format(p / inputUnit.metres)) \(inputUnit.symbol)")
            if areaUnit.perimeterUnit != inputUnit {
                lines.append("\(sign) \(perimeterText) \(areaUnit.perimeterUnit.symbol)")
            }
        }
        return lines
    }

    // MARK: Share and print

    private var summaryLines: (inputs: [String], results: [String]) {
        let ins = inputs.compactMap { i -> String? in
            let raw = text(i.symbol).trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return nil }
            return "\(i.name) \(i.symbol) = \(ShapeNumber.echo(raw)) \(unitLabel(i))"
        }
        var res: [String] = []
        if let r = result {
            res.append("Area = \(areaText) \(areaUnit.symbol)")
            if r.perimeter != nil {
                res.append("\(perimeterName) \(r.perimeterIsApproximate ? "≈" : "=") \(perimeterText) \(areaUnit.perimeterUnit.symbol)")
            }
            for e in r.extras { res.append("\(e.name) \(e.symbol) = \(extraText(e))") }
            res.append(contentsOf: r.notes)
        } else if let errorMessage {
            res.append(errorMessage)
        }
        return (ins, res)
    }

    private var shareText: String {
        let s = summaryLines
        var lines: [String] = [kind.name]
        lines.append(contentsOf: s.inputs)
        lines.append("")
        lines.append(contentsOf: s.results)
        lines.append(contentsOf: ["", "Formula:"])
        lines.append(contentsOf: formulaLines)
        lines.append(contentsOf: ["", "Calculated with Plumb"])
        return lines.joined(separator: "\n")
    }

    private func printSummary() {
        focused = nil
        let s = summaryLines
        let page = ShapePrintPage(kind: kind, measure: measure, values: rawValues, labelText: diagramLabel,
                                  inputs: s.inputs, results: s.results, formulas: formulaLines, date: Date())
        guard let data = ShapePrinter.pdf(page) else {
            showToast("Couldn't prepare the page")
            return
        }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "\(kind.name) area"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
    }

    // MARK: Actions

    private func index(of symbol: String?) -> Int {
        inputs.firstIndex { $0.symbol == symbol } ?? 0
    }

    private func step(_ delta: Int) {
        let i = min(max(0, index(of: focused) + delta), inputs.count - 1)
        focused = inputs[i].symbol
    }

    private func setInputUnit(_ u: ShapeLengthUnit) {
        // Keep the output unit following the input unit unless the user picked a different one.
        if areaUnit == ShapeAreaUnit.matching(inputUnit) { areaUnitRaw = ShapeAreaUnit.matching(u).rawValue }
        inputUnit = u
    }

    /// Radius <-> diameter keeps the same circle: the value is doubled or halved.
    private func switchMeasure(_ new: CircleMeasure) {
        guard new != measure else { return }
        let (from, to) = new == .diameter ? ("r", "d") : ("d", "r")
        if let v = ShapeNumber.parse(text(from)) {
            texts[to] = Self.plain(new == .diameter ? v * 2 : v / 2)
        } else {
            texts[to] = texts[from] ?? ""
        }
        texts[from] = nil
        measure = new
        Haptics.selection()
    }

    private static func plain(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private func save(to projectID: UUID?) {
        guard result != nil else { return }
        store.add(MeasurementRecord(
            name: "\(kind.name) area",
            value: "\(areaText) \(areaUnit.symbol)",
            source: .calculated,
            tool: .calculator,
            projectID: projectID,
            date: Date()
        ))
        let name = store.project(projectID)?.name
        showToast(name.map { "Saved to \($0)" } ?? "Saved to History")
    }

    private func showToast(_ text: String) {
        withAnimation(PM.Motion.normal) { toast = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(PM.Motion.normal) { if toast == text { toast = nil } }
        }
    }
}

// MARK: - Unit chips

/// Horizontally scrolling single-choice chips, 44 pt tall touch targets.
private struct ChipRow<Item: Hashable & Identifiable>: View {
    var items: [Item]
    var selected: Item
    var label: KeyPath<Item, String>
    var spoken: KeyPath<Item, String>
    var inset: CGFloat = 16
    var onSelect: (Item) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        let on = item == selected
                        Button {
                            Haptics.selection()
                            withAnimation(.easeOut(duration: 0.2)) { onSelect(item) }
                        } label: {
                            Text(item[keyPath: label])
                                .font(.pm(14, .bold))
                                .foregroundStyle(on ? PM.Colors.onAccent : PM.Colors.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 50)
                                .frame(height: 34)
                                .background(Capsule().fill(on ? PM.Colors.accent : PM.Colors.surfaceRaised))
                                .overlay(Capsule().strokeBorder(on ? Color.clear : PM.Colors.borderStrong, lineWidth: 1))
                                .frame(height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pmPress)
                        .id(item.id)
                        .accessibilityLabel(item[keyPath: spoken])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, inset)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selected.id, anchor: .center) }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Memory

/// Last inputs per shape, so leaving and coming back keeps the job's numbers.
private enum ShapeMemory {
    struct Saved: Codable {
        var values: [String: String]
        var unit: ShapeLengthUnit
        var measure: CircleMeasure
    }

    static func load(_ kind: ShapeKind) -> Saved? {
        #if DEBUG
        if DebugLaunch.isActive { return nil }
        #endif
        guard let data = UserDefaults.standard.data(forKey: "shape.\(kind.rawValue)") else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    static func save(_ kind: ShapeKind, values: [String: String], unit: ShapeLengthUnit, measure: CircleMeasure) {
        #if DEBUG
        if DebugLaunch.isActive { return }
        #endif
        guard let data = try? JSONEncoder().encode(Saved(values: values, unit: unit, measure: measure)) else { return }
        UserDefaults.standard.set(data, forKey: "shape.\(kind.rawValue)")
    }
}
