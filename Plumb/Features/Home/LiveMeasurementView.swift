//
//  LiveMeasurementView.swift
//  Plumb
//
//  Boards: 02 Signature (Wow.dc.html) and 02b Signature live (WowLive.dc.html).
//  Home's dial zooms into this screen through HomeZoomOverlay; the chrome fades in after it.
//

import SwiftUI

struct LiveMeasurementView: View {
    /// Instrument scale in live mode (board: translateY(12px) scale(1.36)).
    static let dialScale: CGFloat = 1.36

    /// Dial centre in screen coordinates. Board: 236 pt dial at top 214, +12 translate, so centre y 344 on the 844 frame.
    static func dialCentre(width: CGFloat, safeTop: CGFloat) -> CGPoint {
        CGPoint(x: width / 2, y: safeTop + (214 + 118 + 12 - PM.Board.statusBar))
    }

    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var motion = MotionService.shared
    @State private var chromeVisible = false
    @State private var locked: (pitch: Double, roll: Double)?
    @State private var showInfo = false
    @State private var hapticGate = LevelHapticGate()

    private var reading: HomeLevelReading {
        // Simulator preview (Debug, no sensor) shows the board's reading.
        let preview = motion.isPreview
        return HomeLevelReading(pitch: locked?.pitch ?? (preview ? 0.26 : motion.pitch),
                         roll: locked?.roll ?? (preview ? -0.3 : motion.roll),
                         perfectTolerance: settings.perfectTolerance,
                         nearlyTolerance: settings.nearlyTolerance)
    }

    var body: some View {
        if !motion.isAvailable && !motion.isPreview {
            UnavailableStateView(kind: .motionUnavailable)
        } else {
            live
        }
    }

    private var live: some View {
        GeometryReader { safe in
            let top = safe.safeAreaInsets.top
            let bottom = safe.safeAreaInsets.bottom
            GeometryReader { geo in
            let centre = Self.dialCentre(width: geo.size.width, safeTop: top)
            ZStack(alignment: .top) {
                Color.clear

                HomeLevelDial(bubbleOffset: reading.bubbleOffset, drift: !motion.isAvailable && locked == nil)
                    .scaleEffect(Self.dialScale)
                    .position(centre)
                    .accessibilityElement()
                    .accessibilityLabel("Live level instrument")
                    .accessibilityValue(accessibilityValue)

                Group {
                    topBar
                        .padding(.top, top + 58 - PM.Board.statusBar)

                    readout
                        .padding(.top, top + 522 - PM.Board.statusBar)

                    bottomRow
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, bottom > 0 ? bottom : 34)
                }
                .opacity(chromeVisible ? 1 : 0)
                .offset(y: chromeVisible || reduceMotion ? 0 : 10)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // The backdrop's glow is larger than the screen: keep it out of layout.
            .background { GridBackdrop().frame(width: geo.size.width, height: geo.size.height).clipped() }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            motion.start()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3).delay(0.15)) {
                chromeVisible = true
            }
        }
        .onDisappear { motion.stop() }
        .onChange(of: reading.magnitude) { _, m in
            guard locked == nil, !motion.isPreview else { return }
            hapticGate.update(magnitude: m, tolerance: settings.perfectTolerance)
        }
        .sheet(isPresented: $showInfo) { MeasurementInfoSheet() }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            IconCircleButton(icon: .close, label: "Exit live measurement", iconSize: 18, stroke: 2.2, action: exit)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle().fill(PM.Colors.measuring).frame(width: 7, height: 7)
                Text("LIVE MEASUREMENT")
            }
            .font(.pm(12, .heavy))
            .tracking(1.2)
            .foregroundStyle(PM.Colors.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(PM.Colors.surface))
            .overlay(Capsule().strokeBorder(PM.Colors.border, lineWidth: 1))
            Spacer(minLength: 8)
            IconCircleButton(icon: .info, label: "Measurement info", stroke: 1.8) { showInfo = true }
        }
        .padding(.horizontal, 20)
    }

    private var readout: some View {
        let r = reading
        return VStack(spacing: 10) {
            Text(r.magnitudeText)
                .font(.pm(76, .ultraLight))
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(height: 76)

            HStack(spacing: 7) {
                switch r.status {
                case .perfect:
                    PMIcon(.check, size: 15, stroke: 2.6)
                    Text("PERFECTLY LEVEL")
                case .nearly:
                    PMIcon(.nearly, size: 15, stroke: 2.2)
                    Text("NEARLY LEVEL · \(r.directionText)")
                case .off:
                    PMIcon(.arrowUp, size: 15, stroke: 2.2).rotationEffect(.degrees(r.arrowRotation))
                    Text(r.directionText)
                }
            }
            .font(.pm(13, .heavy))
            .tracking(1.4)
            .foregroundStyle(r.status == .perfect ? PM.Colors.accent : PM.Colors.textSecondary)

            if locked != nil {
                StatusPill(state: .aligned, text: "LOCKED", height: 26)
            } else {
                HStack(spacing: 6) {
                    Circle().fill(PM.Colors.measuring).frame(width: 6, height: 6)
                    Text("Sensor · Device motion")
                }
                .font(.pm(12, .semibold))
                .foregroundStyle(PM.Colors.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(PM.Colors.surface))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var bottomRow: some View {
        let r = reading
        return HStack(spacing: 12) {
            HStack(spacing: 22) {
                axis("PITCH", formatSignedDegrees(r.pitch))
                axis("ROLL", formatSignedDegrees(r.roll))
            }
            Spacer(minLength: 0)
            Button(action: toggleLock) {
                HStack(spacing: 8) {
                    PMIcon(.lock, size: 18, stroke: 2)
                    Text(locked == nil ? "Lock" : "Unlock")
                }
                .font(.pm(17, .bold))
                .foregroundStyle(locked == nil ? PM.Colors.onAccent : PM.Colors.accent)
                .padding(.horizontal, 24)
                .frame(height: 54)
                .background(Capsule().fill(locked == nil ? PM.Colors.accent : PM.Colors.background))
                .overlay(Capsule().strokeBorder(locked == nil ? .clear : PM.Colors.accent, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.pmPress)
            .accessibilityAddTraits(locked == nil ? [] : .isSelected)
        }
        .padding(.horizontal, 20)
    }

    private func axis(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.pmMono(12))
                .tracking(1)
                .foregroundStyle(PM.Colors.textSecondary)
            Text(value)
                .font(.pmMono(15))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var accessibilityValue: String {
        let r = reading
        switch r.status {
        case .perfect: return "Perfectly level"
        case .nearly: return "Nearly level, \(r.directionText.lowercased())"
        case .off: return r.directionText.lowercased()
        }
    }

    // MARK: Actions

    private func toggleLock() {
        if locked == nil {
            locked = (motion.pitch, motion.roll)
            Haptics.measurementLocked()
        } else {
            locked = nil
        }
    }

    /// Chrome fades, then Home plays the zoom back to its dial.
    private func exit() {
        withAnimation(.easeIn(duration: reduceMotion ? 0.2 : 0.25)) { chromeVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.2 : 0.25)) {
            HomeZoomCoordinator.shared.pendingReturn = router.path.count == 1
            homeWithoutAnimation { router.pop() }
        }
    }
}
