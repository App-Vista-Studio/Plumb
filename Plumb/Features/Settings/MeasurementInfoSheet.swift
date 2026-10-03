//
//  MeasurementInfoSheet.swift
//  Plumb
//
//  Settings board, phone 2: Measurement Info bottom sheet with live quality, advanced values,
//  sensor availability and (debug builds only) filter tuning.
//

import ARKit
import CoreLocation
import CoreMotion
import SwiftUI

struct MeasurementInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var heading = MeasurementInfoHeading()

    private let motion = MotionService.shared
    private let sunken = Color(dark: 0x0F1316, light: 0xF4F5F2)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Capsule()
                    .fill(PM.Colors.badgeOutline)
                    .frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MEASUREMENT QUALITY").pmCaptionStyle(tracking: 1.3)
                        HStack(spacing: 8) {
                            SVGStroke(d: quality.state.iconPath, size: 20, lineWidth: 2.6)
                            Text(quality.label)
                        }
                        .font(.pm(22, .bold))
                        .foregroundStyle(quality.state.color)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        PMIcon(.close, size: 16, stroke: 2.2)
                            .foregroundStyle(PM.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(PM.Colors.surfaceRaised))
                    }
                    .buttonStyle(.pmPress)
                    .accessibilityLabel("Close measurement info")
                }

                HStack(alignment: .top, spacing: 8) {
                    infoCell("Sensor", motion.isAvailable ? "Device Motion" : "Unavailable")
                    infoCell("Reference", "Gravity")
                    infoCell("Stability", "\(Int((motion.stability * 100).rounded()))%")
                }

                Text("ADVANCED").pmCaptionStyle(tracking: 1.3)
                VStack(spacing: 0) {
                    advancedRow("Pitch", Self.degrees(motion.pitch), first: true)
                    advancedRow("Roll", Self.degrees(motion.roll))
                    advancedRow("Heading", heading.text)
                    advancedRow("Tracking state", motion.isAvailable ? "Normal" : "Unavailable")
                    advancedRow("Calibration state", calibrationText)
                    HStack {
                        Text("Sensor availability").font(.pm(14)).foregroundStyle(PM.Colors.textSecondary)
                        Spacer(minLength: 6)
                        HStack(spacing: 10) {
                            availability("Motion", Self.motionAvailable)
                            availability("Heading", CLLocationManager.headingAvailable())
                            availability("AR", ARWorldTrackingConfiguration.isSupported)
                        }
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 14)
                    .overlay(alignment: .top) { PM.Colors.iconWell.frame(height: 1) }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(sunken))

                #if DEBUG
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEVELOPER TUNING · DEBUG BUILDS ONLY")
                        .font(.pm(12, .bold))
                        .tracking(1.1)
                        .foregroundStyle(PM.Colors.warning)
                    tuningRow("smoothing factor", String(format: "%.2f", motion.smoothing))
                    tuningRow("update interval", "\(Int((1 / motion.updateInterval).rounded())) Hz")
                    tuningRow("settling threshold", "0.05°")
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(PM.Colors.badgeOutline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                #endif
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(640), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .presentationBackground(PM.Colors.surface)
        .onAppear {
            motion.start()
            heading.start()
        }
        .onDisappear {
            motion.stop()
            heading.stop()
        }
    }

    // MARK: Pieces

    private static let motionAvailable = CMMotionManager().isDeviceMotionAvailable

    /// "0.1°", "-0.1°"; never "-0.0°", and "—" for a non-finite reading.
    private static func degrees(_ v: Double) -> String {
        guard v.isFinite else { return "\u{2014}" }
        let r = (v * 10).rounded() / 10
        return String(format: "%.1f°", r == 0 ? 0 : r)
    }

    private var quality: (label: String, state: MeasureState) {
        if !motion.isAvailable { return ("Unavailable", .unavailable) }
        if motion.stability >= 0.9 { return ("Good", .aligned) }
        if motion.stability >= 0.6 { return ("Fair", .warning) }
        return ("Poor", .warning)
    }

    private var calibrationText: String {
        guard let d = motion.calibratedAt else { return "Not calibrated" }
        if Calendar.current.isDateInToday(d) { return "Calibrated today" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "d MMM"
        return "Calibrated \(f.string(from: d))"
    }

    private func infoCell(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k).font(.pm(12)).foregroundStyle(PM.Colors.textSecondary)
            Text(v).font(.pm(14, .semibold)).monospacedDigit().foregroundStyle(PM.Colors.textPrimary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(sunken))
        .accessibilityElement(children: .combine)
    }

    private func advancedRow(_ k: String, _ v: String, first: Bool = false) -> some View {
        HStack {
            Text(k).font(.pm(14)).foregroundStyle(PM.Colors.textSecondary)
            Spacer()
            Text(v).font(.pmMono(14, .semibold)).foregroundStyle(PM.Colors.textPrimary)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .overlay(alignment: .top) { if !first { PM.Colors.iconWell.frame(height: 1) } }
        .accessibilityElement(children: .combine)
    }

    private func availability(_ name: String, _ ok: Bool) -> some View {
        HStack(spacing: 3) {
            SVGStroke(d: ok ? PMIconName.check.d : PMIconName.close.d, size: 12, lineWidth: 3)
                .foregroundStyle(ok ? PM.Colors.accent : PM.Colors.unavailable)
            Text(name)
                .font(.pm(13, .semibold))
                .foregroundStyle(ok ? PM.Colors.textPrimary : PM.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(ok ? "available" : "unavailable")")
    }

    private func tuningRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(PM.Colors.textSecondary)
            Spacer()
            Text(v).foregroundStyle(PM.Colors.textPrimary)
        }
        .font(.pmMono(13))
    }
}

/// Magnetic heading for the Advanced list. Shows "—" where there is no magnetometer (Simulator).
@Observable
final class MeasurementInfoHeading: NSObject, CLLocationManagerDelegate {
    private(set) var degrees: Double?
    @ObservationIgnored private let manager = CLLocationManager()

    var text: String {
        guard let degrees else { return "\u{2014}" }
        return String(format: "%03d°", Int(degrees.rounded()) % 360)
    }

    func start() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.delegate = self
        manager.headingFilter = 1
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.magneticHeading
        guard value >= 0 else { return }
        Task { @MainActor in self.degrees = value }
    }
}
