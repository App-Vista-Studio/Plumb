//
//  CompassView.swift
//  Plumb
//
//  Compass board: rotating card, lubber line, heading accuracy, reduced-accuracy warning.
//

import SwiftUI

struct CompassView: View {
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    private var light: Bool { scheme == .light }

    /// Debug captures only: the board's second phone (True North, ±25°, interference).
    private let fixturePoor = DebugLaunch.is("poor")
    @State private var fixtureNorth: CompassNorth = .trueNorth

    @State private var service = CompassHeadingService()
    /// Continuous heading so the card never spins the long way round at 359° → 0°.
    @State private var unwrapped: Double = 42
    @State private var lockedHeading: Double?
    @State private var showToast = false

    var body: some View {
        let heading = lockedHeading ?? liveHeading
        let poor = isPoor
        let accText = accuracyValue < 0 ? "—" : "±\(Int(accuracyValue.rounded()))°"

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PMTopBar(title: "Compass") {
                    IconCircleButton(icon: .info, label: "Compass help", stroke: 1.8) { router.push(.settings) }
                }

                PMSegmented(options: [(CompassNorth.magnetic, "MAGNETIC NORTH"), (CompassNorth.trueNorth, "TRUE NORTH")],
                            selection: northBinding,
                            segmentHeight: light ? 44 : 40,
                            fontSize: light ? 13 : 12, tracking: light ? 1 : 0.8,
                            trackBorder: light ? .clear : PM.Colors.border,
                            fitContent: true, trackPadding: light ? 4 : 5)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                CompassDial(rotation: lockedHeading ?? unwrapped,
                            headingText: String(format: "%03d°", Int(heading.rounded()) % 360),
                            direction: Self.direction(for: heading),
                            poor: poor)
                    .padding(.top, light ? 20 + 16 : 26)

                // Light board: the two chips wrap onto two centred rows.
                let chipLayout = light ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                chipLayout {
                    LivePill(text: sourceText)
                        .frame(height: light ? 28 : 26)
                    CompassAccuracyChip(text: "Heading accuracy \(accText)", poor: poor)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.top, light ? 16 : 22)

                if !service.isAvailable && !DebugLaunch.isActive {
                    CompassNoticeCard(title: "No compass on this device",
                                      message: "This device doesn't report a magnetic heading, so the compass can't be shown.",
                                      action: nil)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                } else if north == .trueNorth && service.locationAccess == .denied && !DebugLaunch.isActive {
                    CompassNoticeCard(title: "True North needs your location",
                                      message: "Location is off for Plumb, so the heading shown is magnetic. Allow location to correct for declination.",
                                      action: ("Open Settings", {
                                          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                      }))
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                } else if poor {
                    CompassInterferenceCard()
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                } else {
                    Text("Hold your \(Device.name) flat. Keep away from magnets, speakers and metal for a reliable heading.")
                        .font(.pm(light ? 14 : 13))
                        .lineSpacing(light ? 3.6 : 3.4)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, light ? 32 : 28)
                        .padding(.top, light ? 16 : 14)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ToolChromeLockButton(locked: lockedHeading != nil, lockLabel: "Lock heading",
                                     disabled: poor && lockedHeading == nil) {
                    if lockedHeading != nil { lockedHeading = nil }
                    else { lockedHeading = liveHeading; Haptics.measurementLocked() }
                }
                Button { save(heading) } label: { Text("Save").fontWeight(light ? .bold : .semibold) }
                    .buttonStyle(PMSecondaryButtonStyle(horizontalPadding: 22))
            }
            .padding(.horizontal, 20)
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .overlay { if lockedHeading != nil { ToolChromeLockedFrame() } }
        .toolChromeToast($showToast)
        .onAppear {
            service.start(trueNorth: north == .trueNorth)
            unwrapped = liveHeading
        }
        .onDisappear { service.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { service.start(trueNorth: north == .trueNorth) } else if phase == .background { service.stop() }
        }
        .onChange(of: settings.compassNorth) { _, new in service.setTrueNorth(new == .trueNorth) }
        .onChange(of: liveHeading) { old, new in
            let diff = (new - old + 540).truncatingRemainder(dividingBy: 360) - 180
            withAnimation(PM.Motion.bubbleSpring) { unwrapped += diff }
        }
    }

    // MARK: Values

    private var north: CompassNorth { fixturePoor ? fixtureNorth : settings.compassNorth }

    private var northBinding: Binding<CompassNorth> {
        Binding(get: { north }, set: { new in
            if fixturePoor { fixtureNorth = new } else { settings.compassNorth = new }
        })
    }

    /// True North in use: selected, and a location fix has produced a true heading.
    private var usingTrueNorth: Bool { north == .trueNorth && service.isAvailable && service.trueHeading >= 0 }

    private var sourceText: String {
        guard service.isAvailable, north == .trueNorth else { return "Heading · Core Location" }
        if usingTrueNorth { return "True heading · Core Location" }
        return service.locationAccess == .denied ? "Magnetic · location off" : "Finding location…"
    }

    private var liveHeading: Double {
        // Without a heading sensor there is no real reading: show north (0°) rather than an invented one.
        // The board values (42° / 118°) are used only by the debug screenshot launch flags.
        guard service.isAvailable else { return DebugLaunch.isActive ? (fixturePoor ? 118 : 42) : 0 }
        if usingTrueNorth { return service.trueHeading }
        return service.magneticHeading
    }

    private var accuracyValue: Double {
        guard service.isAvailable else { return DebugLaunch.isActive ? (fixturePoor ? 25 : 5) : -1 }
        return service.hasReading ? service.accuracy : -1
    }

    /// Low accuracy (over ±15°, or invalid) or a field far outside Earth's 25–65 µT range means interference.
    private var isPoor: Bool {
        guard service.isAvailable else { return fixturePoor }
        guard service.hasReading else { return false }
        if service.accuracy < 0 || service.accuracy > 15 { return true }
        if let f = service.fieldStrength, f < 15 || f > 100 { return true }
        return false
    }

    static func direction(for heading: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        var h = heading.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return names[Int((h + 22.5) / 45) % 8]
    }

    private func save(_ heading: Double) {
        let text = String(format: "%03d° ", Int(heading.rounded()) % 360) + Self.direction(for: heading)
        MeasurementStore.shared.add(MeasurementRecord(
            name: "Heading", value: text, source: .sensor, tool: .compass, projectID: nil, date: Date()))
        withAnimation(PM.Motion.normal) { showToast = true }
    }
}

// MARK: - Dial

/// 310 pt dial. The card rotates by −heading; the lubber line stays at the top.
private struct CompassDial: View {
    var rotation: Double
    var headingText: String
    var direction: String
    var poor: Bool

    @Environment(\.colorScheme) private var scheme

    private static let faceTop = Color(dark: 0x1A2126, light: 0xFFFFFF)
    private static let faceBottom = Color(dark: 0x0E1215, light: 0xEDF0EC)
    private static let majorTick = Color(dark: 0x8A959B, light: 0x2E353A)
    private static let minorTick = Color(dark: 0x3A444B, light: 0x9AA39E)

    var body: some View {
        ZStack {
            // Face
            if scheme == .light {
                Circle()
                    .fill(AngularGradient(colors: [0xB9C0BB, 0xE9ECE8, 0xA9B1AB, 0xF4F6F3, 0xB9C0BB, 0xDDE1DC, 0xB9C0BB].map { Color(hex: $0) },
                                          center: .center, angle: .degrees(30 - 90)))
                    .shadow(color: Color(hex: 0x0E1113).opacity(0.14), radius: 18, y: 16)
                Circle()
                    .fill(RadialGradient(colors: [Self.faceTop, Self.faceBottom], center: UnitPoint(x: 0.5, y: 0.35),
                                         startRadius: 0, endRadius: 147 * 0.8 * 1.6))
                    .padding(8)
            } else {
                Circle()
                    .fill(RadialGradient(stops: [.init(color: Self.faceTop, location: 0), .init(color: Self.faceBottom, location: 0.72)],
                                         center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 242))
                    .overlay(Circle().strokeBorder(PM.Colors.dialRim, lineWidth: 1))
                    .overlay(Circle().inset(by: 1).trim(from: 0.6, to: 0.9).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: 30, y: 24)
            }

            if scheme == .light {
                CompassLightFace(rotation: rotation).frame(width: 294, height: 294)
            }

            // Ticks: 5° steps, major every 30°, north in accent.
            if scheme != .light {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<72 {
                    let d = i * 5
                    let major = d % 30 == 0
                    let len: CGFloat = major ? 14 : 7
                    let t = Double(d) * .pi / 180
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + sin(t) * 149, y: c.y - cos(t) * 149))
                    p.addLine(to: CGPoint(x: c.x + sin(t) * (149 - len), y: c.y - cos(t) * (149 - len)))
                    let color = d == 0 ? PM.Colors.accent : major ? Self.majorTick : Self.minorTick
                    ctx.stroke(p, with: .color(color), lineWidth: major ? 2 : 1)
                }
            }
            .rotationEffect(.degrees(-rotation))

            CompassCardinals(heading: rotation)
            }

            Circle()
                .fill(scheme == .light ? Color.white : Color.clear)
                .overlay(Circle().strokeBorder(scheme == .light ? PM.Colors.border : PM.Colors.dialLine, lineWidth: 1))
                .shadow(color: scheme == .light ? Color(hex: 0x0E1113).opacity(0.08) : .clear, radius: 7, y: 4)
                .frame(width: 160, height: 160)

            VStack(spacing: 2) {
                Text(headingText)
                    .font(.pm(scheme == .light ? 50 : 48, .light))
                    .tracking(scheme == .light ? -1.5 : -1)
                    .monospacedDigit()
                    .foregroundStyle(PM.Colors.textPrimary)
                    .cssLineBox(fontSize: scheme == .light ? 50 : 48, lineHeight: 1)
                    .contentTransition(.numericText())
                Text(direction)
                    .font(.pm(scheme == .light ? 16 : 18, scheme == .light ? .heavy : .bold))
                    .tracking(scheme == .light ? 1.6 : 2)
                    .foregroundStyle(PM.Colors.textSecondary)
            }
            // Light board: the readout block sits 11.5 pt above the dial centre.
            .offset(y: scheme == .light ? -11.5 : 0)
        }
        .frame(width: 310, height: 310)
        .overlay(alignment: .top) {
            CompassLubber()
                .fill(poor ? PM.Colors.warning : PM.Colors.accent)
                .frame(width: scheme == .light ? 18 : 16, height: 14)
                .offset(y: scheme == .light ? -16 : -14)
        }
        .opacity(poor ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heading \(headingText) \(direction)")
    }
}

/// N NE E … labels that stay upright while their positions follow the card.
private struct CompassCardinals: View, Animatable {
    var heading: Double

    var animatableData: Double {
        get { heading }
        set { heading = newValue }
    }

    private static let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { k in
                let a = (Double(k) * 45 - heading) * .pi / 180
                let main = k % 2 == 0
                Text(Self.names[k])
                    .font(.pm(main ? 16 : 11, main ? .bold : .semibold))
                    .foregroundStyle(k == 0 ? PM.Colors.accent : main ? PM.Colors.textPrimary : PM.Colors.textSecondary)
                    .frame(width: 36)
                    .position(x: 155 + sin(a) * 112, y: 155 - cos(a) * 112)
            }
        }
        .frame(width: 310, height: 310)
    }
}

/// Light board card: ticks and labels drawn on a 294 pt face that turns as one piece.
private struct CompassLightFace: View, Animatable {
    var rotation: Double

    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    private static let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<72 {
                    let b = i * 5
                    let card = b % 90 == 0, mid = b % 45 == 0
                    let len: CGFloat = card ? 16 : mid ? 12 : 7
                    let t = Double(b) * .pi / 180
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + sin(t) * 141, y: c.y - cos(t) * 141))
                    p.addLine(to: CGPoint(x: c.x + sin(t) * (141 - len), y: c.y - cos(t) * (141 - len)))
                    let color: Color = b == 0 ? PM.Colors.accent : (card || mid) ? Color(hex: 0x2E353A) : Color(hex: 0x9AA39E)
                    ctx.stroke(p, with: .color(color), lineWidth: card ? 3 : 1)
                }
            }
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * 45 * .pi / 180
                let card = i % 2 == 0
                Text(Self.names[i])
                    .font(.pm(card ? 17 : 12, card ? .heavy : .bold))
                    .foregroundStyle(i == 0 ? PM.Colors.accent : card ? PM.Colors.textPrimary : PM.Colors.textSecondary)
                    .rotationEffect(.degrees(Double(i) * 45))
                    .position(x: 147 + sin(a) * 112, y: 147 - cos(a) * 112)
            }
        }
        .frame(width: 294, height: 294)
        .rotationEffect(.degrees(-rotation))
        .accessibilityHidden(true)
    }
}

/// Downward triangle: border-top 14, sides 8.
private struct CompassLubber: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct CompassAccuracyChip: View {
    var text: String
    var poor: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            if poor {
                PMIcon(.warning, size: 12, stroke: 2.4)
            } else {
                PMIcon(.check, size: 12, stroke: scheme == .light ? 2.8 : 2.6)
                    .foregroundStyle(scheme == .light ? PM.Colors.accent : PM.Colors.textSecondary)
            }
            Text(text).monospacedDigit()
        }
        .font(.pm(12, scheme == .light && !poor ? .semibold : .bold))
        .foregroundStyle(poor ? PM.Colors.warning : PM.Colors.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: scheme == .light ? 28 : 26)
        .background(Capsule().fill(poor ? CompassInterferenceCard.fill : PM.Colors.surfaceRaised))
        .overlay(Capsule().strokeBorder(scheme == .light && !poor ? PM.Colors.border : .clear, lineWidth: 1))
    }
}

/// Neutral notice with an optional recovery action (no compass, location off).
private struct CompassNoticeCard: View {
    var title: String
    var message: String
    var action: (String, () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.pm(15, .bold)).foregroundStyle(PM.Colors.textPrimary)
            Text(message)
                .font(.pm(13))
                .lineSpacing(3.8)
                .foregroundStyle(PM.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1)
                    .font(.pm(14, .bold))
                    .foregroundStyle(PM.Colors.accent)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .pmCard(radius: 20)
        .accessibilityElement(children: .contain)
    }
}

private struct CompassInterferenceCard: View {
    static let fill = Color(dark: 0x2A2012, light: 0xFFF2DC)
    private static let edge = Color(dark: 0x5A4220, light: 0xE9C98F)
    private static let title = Color(dark: 0xFFD49A, light: 0x8A4B00)
    private static let bodyText = Color(dark: 0xE9D3B4, light: 0x6B4A1E)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SVGShape(d: "M22 11c-5-8-18-8-18 0s13 8 18 0 18-8 18 0-13 8-18 0z", viewBox: CGRect(x: 0, y: 0, width: 44, height: 22))
                .stroke(PM.Colors.warning, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 44, height: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Compass accuracy is currently reduced")
                    .font(.pm(15, .bold))
                    .foregroundStyle(Self.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Improve compass accuracy: move away from metal and wave your \(Device.name) in a figure-eight. Headings near magnetic interference aren't reliable.")
                    .font(.pm(13))
                    .lineSpacing(3.8)
                    .foregroundStyle(Self.bodyText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .pmCard(radius: 20, fill: Self.fill, border: Self.edge)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
