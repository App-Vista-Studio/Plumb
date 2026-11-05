//
//  CalculatorsView.swift
//  Plumb
//
//  Construction calculators (Calculators board): a grid of calculators and a detail screen
//  whose result always shows its formula. Results follow the precision of the inputs.
//
//  Debug: `-screen calculators -state area` opens a calculator directly (any CalcKind raw value).
//

import SwiftUI
import UIKit

struct CalculatorsView: View {
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @State private var open: CalcKind? = CalcKind(rawValue: DebugLaunch.state ?? "")

    var body: some View {
        ZStack {
            if let open {
                CalculatorDetailView(kind: open) {
                    withAnimation(PM.Motion.normal) { self.open = nil }
                }
                .transition(.move(edge: .trailing))
            } else {
                grid
                    .transition(.move(edge: .leading))
            }
        }
        .background(PM.Colors.background.ignoresSafeArea())
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Centred top bar, matching the other tool screens.
                PMTopBar(title: "Calculators", topPadding: 0, horizontalPadding: 0, leading: {
                    IconCircleButton(icon: .back, label: "Back to tools", stroke: 2) { router.pop() }
                }) {
                    TopBarPlaceholder()
                }
                Text("Every result shows its formula.")
                    .font(.pmBody)
                    .foregroundStyle(PM.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Grid (not LazyVGrid) so every tile in a row stretches to the tallest, like CSS grid.
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(0..<3, id: \.self) { row in
                        GridRow {
                            ForEach(CalcKind.allCases[(row * 3)..<(row * 3 + 3)]) { kind in
                                Button { select(kind) } label: { CalcTile(kind: kind, locked: kind.isPro && !settings.isPro) }
                                    .buttonStyle(.pmPress)
                                    .accessibilityLabel("\(kind.title.capitalized) calculator, \(kind.desc)")
                                    .accessibilityValue(kind.isPro && !settings.isPro ? "Pro" : "")
                            }
                        }
                    }
                }
                shapeAreaTile
                HStack(alignment: .top, spacing: 12) {
                    PMIcon(.info, size: 20, stroke: 1.8)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .accessibilityHidden(true)
                    WrapText("Results are estimates for planning. Add a margin for waste and check quantities with your supplier.",
                             size: 13, lineHeight: 1.45, color: PM.Colors.textSecondary)
                }
                .padding(.vertical, 15)
                .padding(.horizontal, 17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pmCard(radius: 20, fill: PM.Colors.surfaceSunken)
            }
            .padding(.top, 56 + 1 - PM.Board.statusBar)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    /// Full-width tile under the grid: opens the Shape Area calculators (free).
    private var shapeAreaTile: some View {
        Button { router.push(.shapes) } label: {
            HStack(spacing: 12) {
                PMIcon(.shapes, size: 22)
                    .foregroundStyle(PM.Colors.accent)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PM.Colors.iconWell))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHAPE AREA")
                        .font(.pm(12, .heavy))
                        .tracking(1)
                        .foregroundStyle(PM.Colors.textPrimary)
                    Text("Area and perimeter of \(ShapeKind.allCases.count) shapes")
                        .font(.pm(12))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PMIcon(.chevronRight, size: 16, stroke: 2)
                    .foregroundStyle(PM.Colors.textTertiary)
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .pmCard()
        }
        .buttonStyle(.pmPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shape area calculators, area and perimeter of \(ShapeKind.allCases.count) shapes")
        .accessibilityAddTraits(.isButton)
    }

    private func select(_ kind: CalcKind) {
        switch kind {
        case .slope, .grade:
            router.push(.slope)
        default:
            if kind.isPro && !settings.isPro {
                router.push(.paywall)
            } else {
                withAnimation(PM.Motion.normal) { open = kind }
            }
        }
    }
}

// MARK: - Tile

private struct CalcTile: View {
    var kind: CalcKind
    var locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.glyph)
                .font(.pm(12, .heavy))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.accent)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minWidth: 38, maxWidth: 50)
                .frame(height: 38)
                .fixedSize(horizontal: true, vertical: false)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PM.Colors.iconWell))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.pm(12, .heavy))
                    .tracking(1)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                WrapText(kind.desc, size: 12, lineHeight: 1.25, color: PM.Colors.textSecondary)
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
        .pmCard()
        .overlay(alignment: .topTrailing) {
            if locked {
                Text("PRO")
                    .font(.pm(12, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(PM.Colors.textSecondary)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .overlay(Capsule().strokeBorder(PM.Colors.badgeOutline, lineWidth: 1))
                    .padding([.top, .trailing], 8)
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

// MARK: - Detail

private struct CalculatorDetailView: View {
    var kind: CalcKind
    var onBack: () -> Void

    @Environment(Router.self) private var router
    @Environment(MeasurementStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var unit: CalcUnit
    @State private var values: [String]
    @State private var toast: String?
    @State private var choosingProject = false
    @State private var naming = false
    @State private var newProjectName = ""
    @State private var choosingFill = false
    @FocusState private var focused: Int?

    init(kind: CalcKind, onBack: @escaping () -> Void) {
        self.kind = kind
        self.onBack = onBack
        let saved = CalcMemory.load(kind)
        _values = State(initialValue: saved?.values ?? kind.fields.map(\.defaultValue))
        _unit = State(initialValue: saved?.unit ?? (AppSettings.shared.units == .imperial ? .ft : .m))
    }

    private var result: CalcResult { kind.compute(values, unit: unit) }

    var body: some View {
        dialogs(chrome(layout))
    }

    private var layout: some View {
        VStack(spacing: 16) {
            ZStack {
                Text(kind.title)
                    .font(.pm(17, .bold))
                    .tracking(1)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    IconCircleButton(icon: .back, label: "Back to calculators", stroke: 2, action: onBack)
                    Spacer()
                    TopBarPlaceholder()
                }
            }
            .frame(height: 46)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if kind.usesUnits {
                        PMSegmented(
                            options: CalcUnit.allCases.map { ($0, $0.rawValue) },
                            selection: $unit,
                            segmentHeight: 44,
                            fontSize: 14,
                            fontWeight: .bold,
                            tracking: 0,
                            gap: 6,
                            fitContent: true,
                            trackPadding: 5
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Units")
                    }
                    fields
                    Button { choosingFill = true } label: {
                        HStack(spacing: 8) {
                            PMIcon(.ar, size: 18).foregroundStyle(PM.Colors.measuring)
                            Text("Fill from AR Measure")
                                .font(.pm(14, .semibold))
                                .foregroundStyle(PM.Colors.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Capsule().fill(PM.Colors.surfaceSunken))
                        .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pmPress)
                    .accessibilityHint("Choose a saved AR distance for \(kind.fields[fillTarget].label)")
                    resultCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 10) {
                Button("Save to project") { choosingProject = true }
                    .buttonStyle(.pmPrimary)
                    .disabled(result.value == nil)
                    .opacity(result.value == nil ? 0.5 : 1)
                Button(action: copy) {
                    PMIcon(.copy, size: 20, stroke: 1.8)
                        .foregroundStyle(PM.Colors.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(PM.Colors.surfaceRaised))
                        .overlay(Circle().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.pmPress)
                .disabled(result.value == nil)
                .accessibilityLabel("Copy result")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .padding(.top, 56 + 1 - PM.Board.statusBar)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func chrome<V: View>(_ v: V) -> some View {
        v.overlay(alignment: .bottom) {
            if let toast {
                ToastView(text: toast)
                    .padding(.bottom, 100)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Previous") { focused = max(0, (focused ?? 0) - 1) }
                    .disabled((focused ?? 0) == 0)
                Button("Next") { focused = min(kind.fields.count - 1, (focused ?? 0) + 1) }
                    .disabled((focused ?? 0) >= kind.fields.count - 1)
                Spacer()
                Button("Done") { focused = nil }.bold()
            }
        }
        .onChange(of: values) { _, new in CalcMemory.save(kind, values: new, unit: unit) }
        .onChange(of: unit) { _, new in CalcMemory.save(kind, values: values, unit: new) }
    }

    private func dialogs<V: View>(_ v: V) -> some View {
        v.confirmationDialog("Save \(result.display)", isPresented: $choosingProject, titleVisibility: .visible) {
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
            Text("Name the real-world job, for example \u{201C}Laundry shelves\u{201D}.")
        }
        .confirmationDialog("Fill \(kind.fields[fillTarget].label)", isPresented: $choosingFill, titleVisibility: .visible) {
            ForEach(recentLengths, id: \.record.id) { item in
                Button("\(item.record.name) \u{00B7} \(item.record.value)") { fill(item.metres) }
            }
            Button("Measure with AR now") { router.push(.ar) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(recentLengths.isEmpty ? "No saved AR distances yet. Measure one, then come back."
                                       : "Pick a saved AR distance. It's converted to \(unit.rawValue).")
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            ForEach(kind.fields.indices, id: \.self) { i in
                let field = kind.fields[i]
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.label).font(.pm(15, .semibold)).foregroundStyle(PM.Colors.textPrimary)
                        Text(fieldError(i) ?? "User-entered")
                            .font(.pm(12, .semibold))
                            .foregroundStyle(fieldError(i) == nil ? PM.Colors.calibrating : PM.Colors.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                    TextField("0", text: Binding(
                        get: { values[i] },
                        set: { values[i] = CalcNumber.limit($0) }
                    ))
                        .keyboardType(.decimalPad)
                        .focused($focused, equals: i)
                        .multilineTextAlignment(.trailing)
                        .font(.pm(20))
                        .monospacedDigit()
                        .foregroundStyle(PM.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(width: 90, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PM.Colors.surfaceRaised))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(fieldError(i) == nil ? PM.Colors.borderStrong : PM.Colors.warning, lineWidth: 1))
                        .accessibilityLabel("\(field.label), \(field.spokenUnit(unit))")
                        .accessibilityHint(fieldError(i) ?? "")
                    Text(field.unitLabel(unit))
                        .font(.pm(15))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 22, alignment: .leading)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture { focused = i }
                if i < kind.fields.count - 1 {
                    PM.Colors.border.frame(height: 1)
                }
            }
        }
        .padding(.vertical, 1)
        .pmCard()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.resultLabel).pmCaptionStyle(tracking: 1.4)
                Spacer()
                Text("Calculated").font(.pm(12, .semibold)).foregroundStyle(PM.Colors.measuring)
            }
            Text(result.display)
                .font(.pm(48, .light))
                .tracking(-1)
                .monospacedDigit()
                .foregroundStyle(result.value == nil ? PM.Colors.textTertiary : PM.Colors.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityLabel(result.value == nil ? "No result yet" : "Result, \(result.spoken)")
            PM.Colors.border.frame(height: 1)
            Text("FORMULA").pmCaptionStyle(tracking: 1)
            WrapText(result.formula, size: 15, lineHeight: 1.5, color: PM.Colors.textPrimary, monospacedDigits: true)
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmCard(radius: 24, fill: PM.Colors.surfaceSunken)
    }

    /// The validation message for a field, or nil when it's fine (empty fields wait silently).
    private func fieldError(_ i: Int) -> String? {
        let raw = values[i].trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        guard let v = CalcNumber(raw).value else { return "Not a number" }
        if kind.fields[i].kind == .count, v != v.rounded() { return "Whole number" }
        if v < 0 { return "Must be positive" }
        if kind.fields[i].mustBePositive, v == 0 { return "Must be more than 0" }
        return nil
    }

    // MARK: Fill from AR

    /// The field AR values go into: the focused length field, else the first empty length field, else the first.
    private var fillTarget: Int {
        if let f = focused, kind.fields.indices.contains(f), kind.fields[f].kind == .length { return f }
        let lengths = kind.fields.indices.filter { kind.fields[$0].kind == .length }
        return lengths.first { values[$0].trimmingCharacters(in: .whitespaces).isEmpty } ?? lengths.first ?? 0
    }

    private var recentLengths: [(record: MeasurementRecord, metres: Double)] {
        store.measurements
            .filter { $0.source == .arDerived || $0.tool == .ar || $0.tool == .room }
            .sorted { $0.date > $1.date }
            .compactMap { r in CalcNumber.metres(fromDisplay: r.value).map { (r, $0) } }
            .prefix(6)
            .map { $0 }
    }

    private func fill(_ metres: Double) {
        let v = metres / unit.metres
        let decimals = unit == .m ? 2 : unit == .cm ? 0 : unit == .ft ? 2 : 1
        values[fillTarget] = CalcNumber.plain(v, decimals)
        Haptics.selection()
    }

    // MARK: Actions

    private func save(to projectID: UUID?) {
        guard result.value != nil else { return }
        store.add(MeasurementRecord(
            name: kind.recordName,
            value: result.display,
            source: .calculated,
            tool: .calculator,
            projectID: projectID,
            date: Date()
        ))
        let name = store.project(projectID)?.name
        showToast(name.map { "Saved to \($0)" } ?? "Saved to History")
    }

    private func copy() {
        guard result.value != nil else { return }
        UIPasteboard.general.string = result.display
        Haptics.selection()
        showToast("Copied")
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

// MARK: - Memory

/// Last inputs per calculator, so leaving and coming back keeps the job's numbers.
private enum CalcMemory {
    struct Saved: Codable { var values: [String]; var unit: String }

    static func load(_ kind: CalcKind) -> (values: [String], unit: CalcUnit)? {
        #if DEBUG
        if DebugLaunch.isActive { return nil }
        #endif
        guard let data = UserDefaults.standard.data(forKey: "calc.\(kind.rawValue)"),
              let s = try? JSONDecoder().decode(Saved.self, from: data),
              s.values.count == kind.fields.count,
              let unit = CalcUnit(rawValue: s.unit) else { return nil }
        return (s.values.map(CalcNumber.limit), unit)
    }

    static func save(_ kind: CalcKind, values: [String], unit: CalcUnit) {
        #if DEBUG
        if DebugLaunch.isActive { return }
        #endif
        guard let data = try? JSONEncoder().encode(Saved(values: values, unit: unit.rawValue)) else { return }
        UserDefaults.standard.set(data, forKey: "calc.\(kind.rawValue)")
    }
}

// MARK: - Model

private enum CalcUnit: String, CaseIterable, Hashable {
    case m, cm, ft, `in`

    /// Metres per unit.
    var metres: Double {
        switch self {
        case .m: 1
        case .cm: 0.01
        case .ft: 0.3048
        case .in: 0.0254
        }
    }

    var spoken: String {
        switch self {
        case .m: "metres"
        case .cm: "centimetres"
        case .ft: "feet"
        case .in: "inches"
        }
    }
}

private struct CalcField {
    enum Kind { case length, count, percent, coverage }
    var label: String
    var defaultValue: String
    var kind: Kind = .length
    /// Zero would divide by zero (tile size, coverage) or make no sense (coats).
    var mustBePositive = false

    func unitLabel(_ unit: CalcUnit) -> String {
        switch kind {
        case .length: unit.rawValue
        case .count: "×"
        case .percent: "%"
        case .coverage: "m²/L"
        }
    }

    func spokenUnit(_ unit: CalcUnit) -> String {
        switch kind {
        case .length: unit.spoken
        case .count: "count"
        case .percent: "percent"
        case .coverage: "square metres per litre"
        }
    }
}

private struct CalcResult {
    var value: Double?
    var display: String
    var formula: String

    /// VoiceOver text: "15.96 square metres".
    var spoken: String {
        display.replacingOccurrences(of: "²", with: " squared").replacingOccurrences(of: "³", with: " cubed")
    }
}

private enum CalcKind: String, CaseIterable, Identifiable {
    case length, area, volume, slope, grade, tile, paint, concrete, material

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var desc: String {
        switch self {
        case .length: "Add and subtract"
        case .area: "Floors and walls"
        case .volume: "Rooms and tanks"
        case .slope: "Rise over run"
        case .grade: "Ramps and paths"
        case .tile: "Tiles and grout"
        case .paint: "Litres per coat"
        case .concrete: "Slabs and footings"
        case .material: "Boards and sheets"
        }
    }

    var glyph: String {
        switch self {
        case .length: "L"
        case .area: "m²"
        case .volume: "m³"
        case .slope: "%"
        case .grade: "1:n"
        case .tile: "pcs"
        case .paint: "L/m²"
        case .concrete: "m³"
        case .material: "qty"
        }
    }

    var isPro: Bool { [.tile, .paint, .concrete, .material].contains(self) }
    var usesUnits: Bool { true }

    var resultLabel: String {
        switch self {
        case .tile: "TILES"
        case .paint: "PAINT"
        case .material: "SHEETS"
        default: title
        }
    }

    var recordName: String {
        switch self {
        case .length: "Length"
        case .area: "Area"
        case .volume: "Volume"
        case .tile: "Tiles"
        case .paint: "Paint"
        case .concrete: "Concrete"
        case .material: "Sheets"
        case .slope, .grade: "Slope"
        }
    }

    var fields: [CalcField] {
        switch self {
        case .length:
            [CalcField(label: "Length", defaultValue: "2.4"),
             CalcField(label: "Add", defaultValue: "1.2"),
             CalcField(label: "Subtract", defaultValue: "0.6")]
        case .area:
            [CalcField(label: "Length", defaultValue: "4.2"),
             CalcField(label: "Width", defaultValue: "3.8")]
        case .volume:
            [CalcField(label: "Length", defaultValue: "4.2"),
             CalcField(label: "Width", defaultValue: "3.8"),
             CalcField(label: "Height", defaultValue: "2.4")]
        case .tile:
            [CalcField(label: "Length", defaultValue: "2.4"),
             CalcField(label: "Width", defaultValue: "1.8"),
             CalcField(label: "Tile width", defaultValue: "0.3", mustBePositive: true),
             CalcField(label: "Tile height", defaultValue: "0.6", mustBePositive: true),
             CalcField(label: "Waste", defaultValue: "10", kind: .percent)]
        case .paint:
            [CalcField(label: "Wall length", defaultValue: "4.2"),
             CalcField(label: "Wall height", defaultValue: "2.4"),
             CalcField(label: "Coats", defaultValue: "2", kind: .count, mustBePositive: true),
             CalcField(label: "Coverage", defaultValue: "12", kind: .coverage, mustBePositive: true)]
        case .concrete:
            [CalcField(label: "Length", defaultValue: "3.0"),
             CalcField(label: "Width", defaultValue: "2.0"),
             CalcField(label: "Depth", defaultValue: "0.1")]
        case .material:
            [CalcField(label: "Length", defaultValue: "4.2"),
             CalcField(label: "Height", defaultValue: "2.4"),
             CalcField(label: "Sheet width", defaultValue: "1.2", mustBePositive: true),
             CalcField(label: "Sheet length", defaultValue: "2.4", mustBePositive: true),
             CalcField(label: "Waste", defaultValue: "10", kind: .percent)]
        case .slope, .grade:
            []
        }
    }

    func compute(_ raw: [String], unit: CalcUnit) -> CalcResult {
        let u = unit.rawValue
        let nums = raw.map { CalcNumber($0) }
        func fail(_ why: String) -> CalcResult {
            CalcResult(value: nil, display: "—", formula: formulaHeader + "\n" + why)
        }
        let defs = fields
        guard nums.count == defs.count else { return fail("Enter every value to see the result.") }
        for (i, n) in nums.enumerated() {
            guard let v = n.value else {
                return fail(raw[i].trimmingCharacters(in: .whitespaces).isEmpty
                            ? "Enter every value to see the result."
                            : "\(defs[i].label) isn't a number.")
            }
            if v < 0 { return fail("\(defs[i].label) can't be negative.") }
            if defs[i].mustBePositive, v == 0 { return fail("\(defs[i].label) must be more than 0.") }
            if defs[i].kind == .count, v != v.rounded() { return fail("\(defs[i].label) must be a whole number.") }
        }
        let v = nums.map { $0.value ?? 0 }
        let dp = nums.map(\.decimals)
        // Show inputs as the user typed them, but with a decimal point.
        let s = nums.map(\.normalised)

        let out: CalcResult
        switch self {
        case .length:
            let r = v[0] + v[1] - v[2]
            if r < 0 { return fail("Subtract is larger than Length + Add.") }
            let text = CalcNumber.format(r, dp.max() ?? 0) + " \(u)"
            out = CalcResult(value: r, display: text,
                             formula: "\(formulaHeader)\n= \(s[0]) \(u) + \(s[1]) \(u) − \(s[2]) \(u) = \(text)")
        case .area:
            let r = v[0] * v[1]
            let text = CalcNumber.format(r, dp[0] + dp[1]) + " \(u)²"
            out = CalcResult(value: r, display: text,
                             formula: "\(formulaHeader)\n= \(s[0]) \(u) × \(s[1]) \(u) = \(text)")
        case .volume, .concrete:
            let r = v[0] * v[1] * v[2]
            let text = CalcNumber.format(r, dp[0] + dp[1] + dp[2]) + " \(u)³"
            var formula = "\(formulaHeader)\n= \(s[0]) \(u) × \(s[1]) \(u) × \(s[2]) \(u) = \(text)"
            if self == .concrete, unit != .m {
                let m3 = r * pow(unit.metres, 3)
                formula += "\n= \(CalcNumber.format(m3, 3)) m³"
            }
            out = CalcResult(value: r, display: text, formula: formula)
        case .tile, .material:
            let pieceArea = v[2] * v[3]
            let area = v[0] * v[1]
            let factor = 1 + v[4] / 100
            let exact = area * factor / pieceArea
            guard exact.isFinite, exact < 1e9 else { return fail("These sizes give too many pieces to count.") }
            let count = Int(ceil(exact - 1e-9))
            let noun = self == .tile ? (count == 1 ? "tile" : "tiles") : (count == 1 ? "sheet" : "sheets")
            let text = "\(CalcNumber.format(Double(count), 0)) \(noun)"
            let areaText = CalcNumber.format(area, dp[0] + dp[1])
            let pieceText = CalcNumber.format(pieceArea, dp[2] + dp[3])
            let factorText = CalcNumber.format(factor, max(2, dp[4] + 2)).trimmingTrailingZeros
            out = CalcResult(value: Double(count), display: text,
                             formula: "\(formulaHeader)\n= \(areaText) \(u)² × \(factorText) ÷ \(pieceText) \(u)², rounded up = \(text)")
        case .paint:
            let areaM2 = v[0] * v[1] * unit.metres * unit.metres
            let litres = areaM2 * v[2] / v[3]
            let text = CalcNumber.format(litres, 1) + " L"
            out = CalcResult(value: litres, display: text,
                             formula: "\(formulaHeader)\n= \(CalcNumber.format(areaM2, 2)) m² × \(s[2]) ÷ \(s[3]) m²/L = \(text)")
        case .slope, .grade:
            return fail("")
        }
        guard let value = out.value, value.isFinite else { return fail("That result is too large to show.") }
        return out
    }

    private var formulaHeader: String {
        switch self {
        case .length: "Length = Length + Add − Subtract"
        case .area: "Area = Length × Width"
        case .volume: "Volume = Length × Width × Height"
        case .concrete: "Concrete = Length × Width × Depth"
        case .tile: "Tiles = Area × (1 + Waste) ÷ Tile area"
        case .material: "Sheets = Area × (1 + Waste) ÷ Sheet area"
        case .paint: "Paint = Wall area × Coats ÷ Coverage"
        case .slope, .grade: "Slope % = Rise ÷ Run × 100"
        }
    }
}

/// A user-entered number and the decimal places it was typed with.
///
/// Accepts digits with one decimal point or decimal comma ("4.2", "4,2", ".5", "5."), surrounding spaces
/// and a leading minus. Rejects exponents, "inf", "nan", letters and repeated separators.
private struct CalcNumber {
    var value: Double?
    var decimals: Int
    /// The input with a decimal point, e.g. "4,20" -> "4.20".
    var normalised: String

    /// Longest input kept in a field. Nine integer digits is far beyond any building measurement.
    nonisolated static let maxLength = 12

    init(_ raw: String) {
        var t = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        normalised = t
        decimals = 0
        value = nil
        var negative = false
        if t.hasPrefix("-") || t.hasPrefix("\u{2212}") { negative = true; t.removeFirst() }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard !t.isEmpty, parts.count <= 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.contains(where: { !$0.isEmpty }) else { return }
        decimals = parts.count == 2 ? parts[1].count : 0
        guard let v = Double((parts[0].isEmpty ? "0" : String(parts[0])) + "." + (parts.count == 2 && !parts[1].isEmpty ? String(parts[1]) : "0")),
              v.isFinite else { return }
        value = negative ? -v : v
    }

    /// Trims pasted text to characters a number can contain and caps its length.
    nonisolated static func limit(_ raw: String) -> String {
        let allowed = Set("0123456789.,-\u{2212} ")
        return String(raw.filter { allowed.contains($0) }.prefix(maxLength))
    }

    static func format(_ v: Double, _ decimals: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = abs(v) >= 10_000
        let d = min(max(decimals, 0), 4)
        f.minimumFractionDigits = d
        f.maximumFractionDigits = d
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(d)f", v)
    }

    /// Plain digits for a text field (no grouping).
    static func plain(_ v: Double, _ decimals: Int) -> String {
        String(format: "%.\(min(max(decimals, 0), 4))f", v)
    }

    /// Reads a stored display value such as "4.82 m", "91 cm", "7.97 ft" or "38 in" as metres.
    static func metres(fromDisplay s: String) -> Double? {
        let parts = s.split(separator: " ")
        guard parts.count == 2, let n = CalcNumber(String(parts[0])).value, n >= 0 else { return nil }
        switch parts[1] {
        case "m": return n
        case "cm": return n / 100
        case "mm": return n / 1000
        case "ft": return n * 0.3048
        case "in": return n * 0.0254
        default: return nil
        }
    }
}

private extension String {
    var trimmingTrailingZeros: String {
        guard contains(".") else { return self }
        var s = self
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
