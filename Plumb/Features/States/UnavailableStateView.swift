//
//  UnavailableStateView.swift
//  Plumb
//
//  Honest error and unavailable states (States board). Never a broken tool: each state names the
//  problem and offers the closest alternative.
//
//  Screens that embed this view (rather than pushing `.unavailable`) can pass `onPrimary` /
//  `onSecondary` to override the default routing.
//

import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

struct UnavailableStateView: View {
    var kind: UnavailableKind
    var onPrimary: (() -> Void)? = nil
    var onSecondary: (() -> Void)? = nil

    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showStillLow = false
    @State private var headingCheck = HeadingAccuracyCheck()

    var body: some View {
        Group {
            if kind == .arTrackingLimited {
                TrackingLimitedState(close: back, tryAgain: primary, usePhoto: secondary)
            } else {
                standard
            }
        }
        // Coming back from the Settings app with camera access granted: continue to AR.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, kind == .cameraPermission, onPrimary == nil,
                  AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                  let last = router.path.last, Self.isUnavailable(last) else { return }
            go(.ar)
        }
    }

    // MARK: Standard layout

    private var content: UnavailableContent { UnavailableContent(kind) }

    private var standard: some View {
        VStack(spacing: 20) {
            ZStack {
                Text(content.title)
                    .font(.pmNavTitle)
                    .foregroundStyle(PM.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 52)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    IconCircleButton(icon: .back, label: "Back", stroke: 1.7, action: back)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 44)

            ScrollView {
                VStack(spacing: 24) {
                    UnavailableIllustration(kind: kind)
                        .accessibilityHidden(true)
                    HStack(spacing: 6) {
                        SVGStroke(d: content.chipIcon, size: 14, lineWidth: 1.7)
                            .foregroundStyle(content.chipIconColor)
                        Text(content.chip)
                    }
                    .font(.pm(12, .bold))
                    .tracking(1.2)
                    .foregroundStyle(content.chipText)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(content.chipFill))
                    .accessibilityElement(children: .combine)

                    WrapText(content.heading, size: 24, weight: .bold, tracking: -0.4, lineHeight: 1.2,
                             alignment: .center, color: PM.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, -4)
                    WrapText(content.body, size: 15, lineHeight: 1.5, alignment: .center, color: PM.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical, alignment: .center) { h, _ in h }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)

            VStack(spacing: 12) {
                Button(action: primary) {
                    if headingCheck.isChecking {
                        HStack(spacing: 8) {
                            ProgressView().tint(PM.Colors.onAccent)
                            Text("Checking\u{2026}")
                        }
                    } else {
                        Text(content.primary)
                    }
                }
                .buttonStyle(.pmPrimary)
                Button(content.secondary, action: secondary)
                    .buttonStyle(PMSecondaryButtonStyle(fontSize: 17, fillWidth: true))
            }
        }
        .padding(.top, 56 + 1 - PM.Board.statusBar)
        .padding(.horizontal, 20)
        .padding(.bottom, max(0, 34 - PM.Board.homeIndicator))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PM.Colors.background.ignoresSafeArea())
        .alert("Still low accuracy", isPresented: $showStillLow) {
            Button("Show heading anyway") { go(.compass) }
            Button("Keep calibrating", role: .cancel) {}
        } message: {
            Text("The compass still reports interference. Keep moving your iPhone in a slow figure-eight away from metal.")
        }
    }

    // MARK: Actions

    private func back() {
        if let last = router.path.last, Self.isUnavailable(last) {
            router.pop()
        } else {
            dismiss()
        }
    }

    private func primary() {
        if let onPrimary { return onPrimary() }
        switch kind {
        case .motionUnavailable: go(.ruler)
        case .cameraPermission:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                go(.ar)
            case .notDetermined:
                Task {
                    if await AVCaptureDevice.requestAccess(for: .video) { go(.ar) }
                }
            default:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        case .arUnsupported: go(.photo)
        case .arTrackingLimited: go(.ar)
        case .compassInterference:
            guard !headingCheck.isChecking else { return }
            headingCheck.run { good in
                if good { go(.compass) } else { showStillLow = true }
            }
        }
    }

    private func secondary() {
        if let onSecondary { return onSecondary() }
        switch kind {
        case .motionUnavailable: go(.calculators)
        case .cameraPermission, .arTrackingLimited: go(.photo)
        case .arUnsupported: router.select(.tools)
        case .compassInterference: go(.compass)
        }
    }

    /// Replaces this state with the alternative when it was pushed as a route; otherwise pushes.
    private func go(_ route: Route) {
        if let last = router.path.last, Self.isUnavailable(last) {
            router.path[router.path.count - 1] = route
        } else {
            router.push(route)
        }
    }

    private static func isUnavailable(_ r: Route) -> Bool {
        if case .unavailable = r { return true }
        return false
    }
}

// MARK: - Compass re-check

/// Listens to heading updates for up to three seconds and reports whether accuracy is usable
/// (within 20°). Devices without a magnetometer report not usable straight away.
@Observable
private final class HeadingAccuracyCheck: NSObject, CLLocationManagerDelegate {
    private(set) var isChecking = false
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var completion: ((Bool) -> Void)?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    func run(_ done: @escaping (Bool) -> Void) {
        guard CLLocationManager.headingAvailable() else { done(false); return }
        isChecking = true
        completion = done
        let m = CLLocationManager()
        m.delegate = self
        m.headingFilter = kCLHeadingFilterNone
        manager = m
        m.startUpdatingHeading()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.finish(false)
        }
    }

    private func finish(_ good: Bool) {
        guard isChecking else { return }
        isChecking = false
        timeout?.cancel()
        manager?.stopUpdatingHeading()
        manager = nil
        let c = completion
        completion = nil
        c?(good)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let acc = newHeading.headingAccuracy
        Task { @MainActor [weak self] in
            if acc >= 0, acc <= 20 { self?.finish(true) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.finish(false) }
    }
}

// MARK: - Content

private struct UnavailableContent {
    var title: String
    var chip: String
    var chipIcon: String
    var chipIconColor: Color
    var chipText: Color
    var chipFill: Color
    var heading: String
    var body: String
    var primary: String
    var secondary: String

    private static let slash = "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0 M5.6 5.6l12.8 12.8"
    private static let lock = "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z M8 11V8a4 4 0 0 1 8 0v3"
    private static let warn = "M12 3l10 18H2z M12 10v5M12 18v.5"

    init(_ kind: UnavailableKind) {
        chipText = PM.Colors.textSecondary
        chipFill = PM.Colors.surfaceRaised
        chipIconColor = PM.Colors.unavailable
        chipIcon = Self.slash
        switch kind {
        case .motionUnavailable:
            title = "Bubble Level"
            chip = "UNAVAILABLE"
            heading = "Motion data isn't available on this device."
            body = "Level, Angle and Protractor need the motion sensor. It may be turned off, or this device doesn't report it."
            primary = "Use Ruler instead"
            secondary = "Open Calculators"
        case .cameraPermission:
            title = "AR Measure"
            chip = "PERMISSION NEEDED"
            chipIcon = Self.lock
            chipIconColor = PM.Colors.textSecondary
            heading = "Camera access is required for this measurement."
            body = "The camera stays on your iPhone. Nothing is recorded or uploaded unless you save a photo."
            primary = "Open Settings"
            secondary = "Measure a photo from your library"
        case .arUnsupported, .arTrackingLimited:
            title = "AR Measure"
            chip = "NOT SUPPORTED"
            heading = "AR Measure isn't available on this device."
            body = "It needs an iPhone with ARKit world tracking. You can still measure from a photo using something of known size, like an A4 sheet."
            primary = "Use Photo Measure"
            secondary = "See all tools"
        case .compassInterference:
            title = "Compass"
            chip = "LOW ACCURACY"
            chipIcon = Self.warn
            chipIconColor = PM.Colors.warning
            chipText = PM.Colors.warning
            chipFill = PM.Colors.warningFill
            heading = "Compass accuracy is currently reduced."
            body = "Move your iPhone in a slow figure-eight a few times. Keep away from metal, magnets, cars and speakers. Readings aren't reliable near magnetic interference."
            primary = "I've moved away, check again"
            secondary = "Show heading anyway"
        }
    }
}

// MARK: - Illustrations

private struct UnavailableIllustration: View {
    var kind: UnavailableKind

    var body: some View {
        switch kind {
        case .motionUnavailable:
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(dark: 0x171D21, light: 0xFFFFFF), PM.Colors.dialFaceBottom],
                                         center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 84 * 0.7 * 1.3))
                    .overlay(Circle().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                Circle()
                    .strokeBorder(PM.Colors.tickMinor, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 88, height: 88)
                Circle().fill(PM.Colors.borderStrong).frame(width: 28, height: 28)
                PM.Colors.unavailable
                    .frame(width: 120, height: 2)
                    .rotationEffect(.degrees(-35))
            }
            .frame(width: 168, height: 168)

        case .cameraPermission:
            SVGStroke(d: PMIconName.camera.d, size: 64, lineWidth: 1.2)
                .foregroundStyle(PM.Colors.textSecondary)
                .frame(width: 168, height: 124)
                .pmCard(radius: 28, fill: PM.Colors.surfaceSunken, border: PM.Colors.borderStrong)

        case .arUnsupported, .arTrackingLimited:
            SVGStroke(d: PMIconName.ar.d, size: 76, lineWidth: 1.1)
                .foregroundStyle(PM.Colors.unavailable)
                .frame(width: 168, height: 168)
                .background(Circle().fill(PM.Colors.surfaceSunken))
                .overlay(Circle().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))

        case .compassInterference:
            ZStack(alignment: .topLeading) {
                Circle().strokeBorder(PM.Colors.tickMinor, lineWidth: 2)
                    .frame(width: 80, height: 80).offset(x: 10, y: 20)
                Circle().strokeBorder(PM.Colors.tickMinor, lineWidth: 2)
                    .frame(width: 80, height: 80).offset(x: 110, y: 20)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PM.Colors.background)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(PM.Colors.warning, lineWidth: 2))
                    .frame(width: 28, height: 32).offset(x: 86, y: 44)
            }
            .frame(width: 200, height: 120, alignment: .topLeading)
        }
    }
}

// MARK: - AR tracking limited

/// Camera overlay state. Camera UI stays dark in both appearances, so it uses fixed colours.
private struct TrackingLimitedState: View {
    var close: () -> Void
    var tryAgain: () -> Void
    var usePhoto: () -> Void

    private let ink = Color(hex: 0x0B0D0F)
    private let text = Color(hex: 0xF1F4F3)
    private let secondary = Color(hex: 0xA7B0B5)
    private let amber = Color(hex: 0xFFB547)
    private let edge = Color(hex: 0x2A3238)

    var body: some View {
        ZStack {
            wall.ignoresSafeArea()
            VStack(spacing: 0) {
                // Top bar: board top 56 = 9 below the status bar.
                ZStack {
                    HStack(spacing: 8) {
                        SVGStroke(d: "M12 3l10 18H2z M12 10v5M12 18v.5", size: 14, lineWidth: 1.7)
                        Text("LIMITED TRACKING").font(.pm(12, .bold)).tracking(1.2)
                    }
                    .foregroundStyle(amber)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(ink.opacity(0.85)))
                    .accessibilityElement(children: .combine)
                    HStack {
                        Button(action: close) {
                            PMIcon(.close, size: 20, stroke: 1.7)
                                .foregroundStyle(text)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(ink.opacity(0.72)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.pmPress)
                        .accessibilityLabel("Close AR Measure")
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56 - PM.Board.statusBar)

                Spacer(minLength: 16)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        WrapText("Move your iPhone slowly and give the camera more visual detail.",
                                 size: 18, weight: .bold, lineHeight: 1.3, color: text)
                        WrapText("Plain walls and dim light are hard to track. Point at an edge, a textured floor or a well-lit object. Measuring is paused until tracking improves.",
                                 size: 14, lineHeight: 1.45, color: secondary)
                    }
                    .padding(21)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ink.opacity(0.9)))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(edge, lineWidth: 1))

                    HStack(spacing: 12) {
                        Button("Try again", action: tryAgain)
                            .buttonStyle(.pmPrimary)
                        Button(action: usePhoto) {
                            Text("Use a photo")
                                .font(.pm(17, .semibold))
                                .foregroundStyle(text)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 21)
                                .frame(height: 54)
                                .background(Capsule().fill(ink.opacity(0.85)))
                                .overlay(Capsule().strokeBorder(edge, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pmPress)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(0, 34 - PM.Board.homeIndicator))
            }
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    /// Dimmed plain wall with a switch plate, vignette, legibility gradients and sparse feature points.
    private var wall: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(stops: [.init(color: Color(hex: 0xC9CCCB), location: 0),
                                           .init(color: Color(hex: 0xD9DBD9), location: 0.45),
                                           .init(color: Color(hex: 0xCDD0CE), location: 1)],
                                   startPoint: UnitPoint(x: 0, y: 0.46), endPoint: UnitPoint(x: 1, y: 0.54))
                    EllipseGlow(center: CGPoint(x: 0.4 * w, y: 0.35 * h), radii: CGSize(width: 0.7 * w, height: 0.55 * h),
                                stops: [.init(color: .white.opacity(0.35), location: 0), .init(color: .white.opacity(0), location: 0.7)])
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: 0xE6E8E6))
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .overlay(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: 0xF7F8F7))
                                .shadow(color: .black.opacity(0.2), radius: 0.5, y: 1)
                                .frame(width: 10, height: 18)
                                .offset(x: 12, y: 18)
                        }
                        .frame(width: 34, height: 54)
                        .offset(x: 250 / PM.Board.width * w, y: 420 / PM.Board.height * h)
                }
                .colorMultiply(Color(white: 0.72))
                .saturation(0.7)

                EllipseGlow(center: CGPoint(x: 0.5 * w, y: 0.48 * h), radii: CGSize(width: 0.95 * w, height: 0.8 * h),
                            stops: [.init(color: .black.opacity(0), location: 0.55), .init(color: .black.opacity(0.42), location: 1)])
                LinearGradient(colors: [Color(hex: 0x060809, opacity: 0.72), Color(hex: 0x060809, opacity: 0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
                LinearGradient(colors: [Color(hex: 0x060809, opacity: 0), Color(hex: 0x060809, opacity: 0.78)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 360)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Canvas { ctx, _ in
                    var y: CGFloat = 0
                    while y < 200 {
                        var x: CGFloat = 0
                        while x < 310 {
                            ctx.fill(Path(ellipseIn: CGRect(x: x + 23 - 1.5, y: y + 19 - 1.5, width: 3, height: 3)),
                                     with: .color(.white.opacity(0.9)))
                            x += 46
                        }
                        y += 38
                    }
                }
                .frame(width: 310, height: 200)
                .opacity(0.55)
                .offset(x: 39 / PM.Board.width * w, y: 300 / PM.Board.height * h)
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
        .background(Color(hex: 0x1A2024))
        .accessibilityHidden(true)
    }
}

/// CSS `radial-gradient(ellipse rx ry at x y, ...)`: an elliptical gradient with explicit radii.
private struct EllipseGlow: View {
    var center: CGPoint
    var radii: CGSize
    var stops: [Gradient.Stop]

    var body: some View {
        Canvas { ctx, size in
            // The ellipse is drawn large enough to cover the canvas; the gradient pads with its last stop.
            guard radii.width > 0, radii.height > 0 else { return }
            var c = ctx
            c.translateBy(x: center.x, y: center.y)
            c.scaleBy(x: radii.width, y: radii.height)
            let r = max(size.width / radii.width, size.height / radii.height) * 2 + 2
            c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(stops: stops), center: .zero, startRadius: 0, endRadius: 1))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Wrapping text

/// Multi-line text that wraps like the boards' CSS: greedy line breaks (SwiftUI `Text` avoids
/// one-word last lines, which moves words the board keeps on the first line) and an exact CSS
/// `line-height` with the leading split above and below each line. Scales with Dynamic Type.
struct WrapText: UIViewRepresentable {
    var text: String
    var size: CGFloat
    var weight: UIFont.Weight = .regular
    var tracking: CGFloat = 0
    /// CSS line-height multiple; nil keeps the font's natural line height.
    var lineHeight: CGFloat?
    var alignment: NSTextAlignment = .natural
    var color: Color
    var underline = false
    var monospacedDigits = false

    init(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, tracking: CGFloat = 0,
         lineHeight: CGFloat? = nil, alignment: NSTextAlignment = .natural, color: Color, underline: Bool = false,
         monospacedDigits: Bool = false) {
        self.monospacedDigits = monospacedDigits
        self.text = text
        self.size = size
        self.weight = weight
        self.tracking = tracking
        self.lineHeight = lineHeight
        self.alignment = alignment
        self.color = color
        self.underline = underline
    }

    func makeUIView(context: Context) -> UILabel {
        let l = UILabel()
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        l.lineBreakStrategy = []
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        l.setContentHuggingPriority(.defaultHigh, for: .vertical)
        l.isAccessibilityElement = true
        return l
    }

    func updateUIView(_ l: UILabel, context: Context) {
        let base = monospacedDigits ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                                    : UIFont.systemFont(ofSize: size, weight: weight)
        let category = UIContentSizeCategory(context.environment.dynamicTypeSize)
        let font = UIFontMetrics.default.scaledFont(for: base, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        let scale = font.pointSize / size
        let p = NSMutableParagraphStyle()
        p.alignment = alignment
        p.lineBreakMode = .byWordWrapping
        p.lineBreakStrategy = []
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: tracking * scale,
            .foregroundColor: UIColor(color),
            .paragraphStyle: p,
        ]
        if let lineHeight {
            let lh = size * lineHeight * scale
            p.minimumLineHeight = lh
            p.maximumLineHeight = lh
            attrs[.baselineOffset] = (lh - font.lineHeight) / 4
        }
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        l.attributedText = NSAttributedString(string: text, attributes: attrs)
        l.accessibilityLabel = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let fit = uiView.sizeThatFits(CGSize(width: width.isFinite ? width : 10_000, height: .greatestFiniteMagnitude))
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : fit.width } ?? fit.width, height: ceil(fit.height))
    }
}

private extension UIContentSizeCategory {
    init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        @unknown default: self = .large
        }
    }
}
