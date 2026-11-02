//
//  SettingsView.swift
//  Plumb
//
//  Settings board, phone 1: measurement, compass, feel and accessibility, and links.
//  Phone 2 (Measurement Info) is `MeasurementInfoSheet` in MeasurementInfoSheet.swift.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var showInfo = DebugLaunch.is("info")
    @State private var message: PaywallMessage?
    @State private var restoring = false

    private let motion = MotionService.shared

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                sectionCaption("MEASUREMENT")
                VStack(spacing: 0) {
                    SettingsRow(divider: true) {
                        Text("Units").font(.pm(15)).foregroundStyle(PM.Colors.textPrimary)
                        Spacer(minLength: 10)
                        SettingsChoice(options: [(UnitSystem.metric, "Metric"), (.imperial, "Imperial")],
                                       selection: $settings.units)
                    }
                    SettingsRow(divider: true) {
                        SettingsLabel(title: "Perfectly level within", hint: "Shows the check mark")
                        Spacer(minLength: 10)
                        SettingsStepper(value: $settings.perfectTolerance,
                                        range: 0.1...max(0.1, settings.nearlyTolerance - 0.1),
                                        name: "perfectly level tolerance")
                    }
                    SettingsRow(divider: false) {
                        SettingsLabel(title: "Nearly level within", hint: "Above this: needs adjustment")
                        Spacer(minLength: 10)
                        SettingsStepper(value: $settings.nearlyTolerance,
                                        range: (settings.perfectTolerance + 0.1)...5.0,
                                        name: "nearly level tolerance")
                    }
                }
                .padding(.vertical, 1)
                .pmCard(radius: 20)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Compass north").font(.pm(15)).foregroundStyle(PM.Colors.textPrimary)
                        Spacer(minLength: 10)
                        SettingsChoice(options: [(CompassNorth.magnetic, "Magnetic"), (.trueNorth, "True")],
                                       selection: $settings.compassNorth)
                    }
                        WrapText("True North points to the geographic North Pole; Magnetic North follows Earth's magnetic field. True North needs Location.",
                             size: 12, lineHeight: 1.45, color: PM.Colors.textSecondary)
                }
                .padding(.top, 11)
                .padding(.leading, 15)
                .padding(.trailing, 13)
                .padding(.bottom, 13)
                .pmCard(radius: 20)

                sectionCaption("FEEL AND ACCESSIBILITY")
                VStack(spacing: 0) {
                    SettingsRow(divider: true, minHeight: 52, vertical: 6) {
                        SettingsLabel(title: "Haptics", hint: "Level reached, lock, save")
                        Spacer(minLength: 10)
                        SettingsSwitch(isOn: $settings.hapticsEnabled, label: "Haptics")
                    }
                    SettingsRow(divider: true, minHeight: 52, vertical: 6) {
                        SettingsLabel(title: "Reduce Motion", hint: "Follows iOS setting")
                        Spacer(minLength: 10)
                        SettingsSwitch(isOn: Binding(get: { settings.reducesMotion(system: systemReduceMotion) },
                                                     set: { settings.reduceMotionOverride = ($0 == systemReduceMotion) ? nil : $0 }),
                                       label: "Reduce Motion")
                    }
                    SettingsRow(divider: false, minHeight: 52, vertical: 6) {
                        SettingsLabel(title: "High-contrast readouts", hint: "Thicker ticks, larger numbers")
                        Spacer(minLength: 10)
                        SettingsSwitch(isOn: $settings.highContrastReadouts, label: "High-contrast readouts")
                    }
                }
                .padding(.vertical, 1)
                .pmCard(radius: 20)

                VStack(spacing: 0) {
                    SettingsLink(title: "Calibration", value: calibrationText, divider: true) { router.push(.calibration) }
                    SettingsLink(title: "Restore Purchases", value: restoring ? "Checking\u{2026}" : "", divider: true) { restore() }
                    SettingsLink(title: "Privacy", value: "No data leaves your phone", divider: false) { message = .privacy }
                }
                .padding(.vertical, 1)
                .pmCard(radius: 20)
            }
            .padding(.top, 52 + 1 - PM.Board.statusBar)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(PM.Colors.background.ignoresSafeArea())
        .sheet(isPresented: $showInfo) {
            MeasurementInfoSheet()
        }
        .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
               presenting: message) { _ in
            Button("OK", role: .cancel) {}
        } message: { m in
            Text(m.body)
        }
    }

    private func restore() {
        guard !restoring else { return }
        restoring = true
        Task {
            message = await ProStore.shared.restore()
            restoring = false
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BackButton()
            Text("Settings")
                .font(.pm(26, .bold))
                .tracking(-0.5)
                .foregroundStyle(PM.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            IconCircleButton(icon: .info, label: "Measurement info", stroke: 1.8) { showInfo = true }
        }
        .frame(height: 46) // board links are 44 + a 1 px border outside the box
    }

    private func sectionCaption(_ s: String) -> some View {
        Text(s)
            .pmCaptionStyle(tracking: 1.3)
            .padding(.top, 4)
            .padding(.horizontal, 4)
    }

    private var calibrationText: String {
        guard let d = motion.calibratedAt else { return "Not set" }
        if Calendar.current.isDateInToday(d) { return "Today" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}

// MARK: - Rows and controls

struct SettingsRow<Content: View>: View {
    var divider: Bool
    var minHeight: CGFloat = 0
    var vertical: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Spacing 0 so the Spacer between label and control doesn't add two 10 pt gaps.
        HStack(spacing: 0) { content() }
            .padding(.vertical, vertical)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(minHeight: minHeight)
            .overlay(alignment: .bottom) {
                if divider { PM.Colors.border.frame(height: 1) }
            }
    }
}

struct SettingsLabel: View {
    var title: String
    var hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.pm(15)).foregroundStyle(PM.Colors.textPrimary)
            Text(hint).font(.pm(12)).foregroundStyle(PM.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hugging two-option control: sunken track (2 pt padding, radius 20), 44 pt segments, radius 18 thumb.
struct SettingsChoice<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let on = value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = value }
                    Haptics.selection()
                } label: {
                    Text(label)
                        .font(.pm(13, .bold))
                        .foregroundStyle(on ? PM.Colors.onThumb : PM.Colors.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? PM.Colors.thumb : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(PM.Colors.background))
    }
}

/// − value + with 44 pt round buttons, 0.1° steps.
struct SettingsStepper: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var name: String

    var body: some View {
        HStack(spacing: 4) {
            button("\u{2212}", label: "Decrease \(name)", enabled: value - 0.05 > range.lowerBound) { step(-0.1) }
            Text(String(format: "%.1f°", value))
                .font(.pm(15, .semibold))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(width: 44)
            button("+", label: "Increase \(name)", enabled: value + 0.05 < range.upperBound) { step(0.1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(String(format: "%.1f degrees", value))
    }

    private func step(_ d: Double) {
        let next = ((value + d) * 10).rounded() / 10
        value = min(range.upperBound, max(range.lowerBound, next))
        Haptics.selection()
    }

    private func button(_ glyph: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.pm(18))
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(PM.Colors.surfaceRaised))
                .overlay(Circle().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.pmPress)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

/// 51 x 31 switch in a 60 x 44 hit area: mint when on, #3A444B when off, white 27 pt knob.
struct SettingsSwitch: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isOn.toggle() }
            Haptics.selection()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? PM.Colors.accent : PM.Colors.tickMinor)
                Circle().fill(Color.white)
                    .frame(width: 27, height: 27)
                    .padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
            .frame(width: 51, height: 31)
            .frame(width: 60, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

struct SettingsLink: View {
    var title: String
    var value: String
    var divider: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.pm(15))
                    .foregroundStyle(PM.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !value.isEmpty {
                    Text(value).font(.pm(13)).foregroundStyle(PM.Colors.textSecondary)
                }
                PMIcon(.chevronRight, size: 16, stroke: 2).foregroundStyle(PM.Colors.textSecondary)
            }
            .padding(.vertical, 6)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) {
                if divider { PM.Colors.border.frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
