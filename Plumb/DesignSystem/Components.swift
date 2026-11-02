//
//  Components.swift
//  Plumb
//
//  Shared controls from the Design system board and COMPONENTS.md.
//  Feature screens compose these; anything used on one screen only lives with that screen.
//

import SwiftUI

// MARK: - Card surface

extension View {
    /// Rounded surface with a 1 pt border. Defaults to the standard card (22, surface, border).
    func pmCard(radius: CGFloat = PM.Radius.card,
                fill: Color = PM.Colors.surface,
                border: Color = PM.Colors.border,
                lineWidth: CGFloat = 1) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(border, lineWidth: lineWidth)
        )
    }
}

// MARK: - Buttons

/// Primary pill: 54 tall, mint fill, dark text, 17 bold.
struct PMPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(fontSize, .bold))
            .foregroundStyle(PM.Colors.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(configuration.isPressed ? PM.Colors.accentPressed : PM.Colors.accent))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Secondary pill: raised surface, strong border, 16 semibold. Hugs its label with 20 side padding.
struct PMSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    var fontSize: CGFloat = 16
    var horizontalPadding: CGFloat = 20
    var fillWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(fontSize, .semibold))
            .foregroundStyle(PM.Colors.textPrimary)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .frame(height: height)
            .background(Capsule().fill(PM.Colors.surfaceRaised))
            .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Outline accent pill (the "Unlock" state of lock buttons): background fill, 1 pt accent border, accent text.
struct PMOutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(fontSize, .bold))
            .foregroundStyle(PM.Colors.accent)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(PM.Colors.background))
            .overlay(Capsule().strokeBorder(PM.Colors.accent, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Card press: scale 1.00 -> 0.97 -> 1.00 over 120 ms. Use on tappable cards and tiles.
struct PMPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PMPrimaryButtonStyle {
    static var pmPrimary: PMPrimaryButtonStyle { PMPrimaryButtonStyle() }
}
extension ButtonStyle where Self == PMSecondaryButtonStyle {
    static var pmSecondary: PMSecondaryButtonStyle { PMSecondaryButtonStyle() }
}
extension ButtonStyle where Self == PMOutlineButtonStyle {
    static var pmOutline: PMOutlineButtonStyle { PMOutlineButtonStyle() }
}
extension ButtonStyle where Self == PMPressStyle {
    static var pmPress: PMPressStyle { PMPressStyle() }
}

/// 44 pt round icon button used in top bars.
struct IconCircleButton: View {
    var icon: PMIconName
    var label: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
    var stroke: CGFloat = 1.7
    var fill: Color = PM.Colors.surface
    var border: Color = PM.Colors.border
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PMIcon(icon, size: iconSize, stroke: stroke)
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pmPress)
        .accessibilityLabel(label)
    }
}

/// Back button: chevron at stroke 2.
struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    var action: (() -> Void)?

    var body: some View {
        IconCircleButton(icon: .back, label: "Back", stroke: 2) {
            if let action { action() } else { dismiss() }
        }
    }
}

// MARK: - Top bar

/// Tool screen header: 44 pt buttons at the sides, 17 semibold centred title.
/// Board spec: `padding: 58px 16px 0` from the frame top, which is 11 pt below the safe area.
struct PMTopBar<Leading: View, Trailing: View>: View {
    var title: String
    var topPadding: CGFloat = 58 - PM.Board.statusBar
    var horizontalPadding: CGFloat = 16
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(.pmNavTitle)
                .foregroundStyle(PM.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                leading()
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(height: 44)
        .padding(.top, topPadding)
        .padding(.horizontal, horizontalPadding)
    }
}

/// Empty 44 pt slot that keeps the title centred.
struct TopBarPlaceholder: View {
    var body: some View { Color.clear.frame(width: 44, height: 44) }
}

extension PMTopBar where Leading == BackButton, Trailing == TopBarPlaceholder {
    init(title: String) {
        self.title = title
        self.leading = { BackButton() }
        self.trailing = { TopBarPlaceholder() }
    }
}

extension PMTopBar where Leading == BackButton {
    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.leading = { BackButton() }
        self.trailing = trailing
    }
}

// MARK: - Pills, tags and badges

/// "Sensor · Device motion" pill: 26 tall, raised fill, 6 pt dot, 12 semibold secondary text.
struct LivePill: View {
    var text: String
    var dot: Color = PM.Colors.measuring

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.pm(12, .semibold))
        .foregroundStyle(PM.Colors.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(PM.Colors.surfaceRaised))
        .overlay(Capsule().strokeBorder(Color(dark: 0x000000, light: 0xE2E5E1, darkOpacity: 0), lineWidth: 1))
    }
}

/// Semantic measurement states. Every state is icon + word + colour.
enum MeasureState: String, CaseIterable {
    case neutral, calibrating, measuring, aligned, warning, unavailable

    var label: String {
        switch self {
        case .neutral: "IDLE"
        case .calibrating: "CALIBRATING"
        case .measuring: "MEASURING"
        case .aligned: "LEVEL"
        case .warning: "LOW ACCURACY"
        case .unavailable: "UNAVAILABLE"
        }
    }

    /// Icon path data (24 grid) from the Design system board.
    var iconPath: String {
        switch self {
        case .neutral: "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z"
        case .calibrating: "M20 11a8 8 0 0 0-14.9-3M4 13a8 8 0 0 0 14.9 3M5 4v4h4M19 20v-4h-4"
        case .measuring: "M3 12h4l3-7 4 14 3-7h4"
        case .aligned: "M5 12l5 5 9-10"
        case .warning: "M12 4l9 16H3zM12 10v4M12 17v.5"
        case .unavailable: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM5.6 5.6l12.8 12.8"
        }
    }

    var color: Color {
        switch self {
        case .neutral: PM.Colors.neutral
        case .calibrating: PM.Colors.calibrating
        case .measuring: PM.Colors.measuring
        case .aligned: PM.Colors.aligned
        case .warning: PM.Colors.warning
        case .unavailable: PM.Colors.unavailable
        }
    }

    var chipFill: Color {
        switch self {
        case .neutral, .unavailable: PM.Colors.surfaceRaised
        case .calibrating: Color(dark: 0x1E2236, light: 0xE9ECFB)
        case .measuring: Color(dark: 0x10283A, light: 0xE3F0F8)
        case .aligned: PM.Colors.accent
        case .warning: Color(dark: 0x2A2113, light: 0xFFF2DC)
        }
    }

    var chipText: Color {
        switch self {
        case .neutral, .unavailable: PM.Colors.textSecondary
        case .aligned: PM.Colors.onAccent
        default: color
        }
    }
}

/// State chip: 28 tall, 12 heavy, tracking 1, 14 pt icon at stroke 2.4.
struct StatusPill: View {
    var state: MeasureState
    var text: String?
    var height: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            SVGStroke(d: state.iconPath, size: 14, lineWidth: 2.4)
            Text(text ?? state.label)
        }
        .font(.pm(12, .heavy))
        .tracking(1)
        .foregroundStyle(state.chipText)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(Capsule().fill(state.chipFill))
    }
}

/// Where a value came from.
enum SourceKind: String, CaseIterable, Codable {
    case sensor = "Sensor"
    case arDerived = "AR-derived"
    case userEntered = "User-entered"
    case calculated = "Calculated"
}

/// Source tag chip: 26 tall pill with a distinct marker per source (dot, square, ring, "=").
struct SourceTag: View {
    var kind: SourceKind

    var body: some View {
        HStack(spacing: 6) {
            marker
            Text(kind.rawValue)
        }
        .font(.pm(12, .semibold))
        .foregroundStyle(PM.Colors.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(PM.Colors.surfaceRaised))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source: \(kind.rawValue)")
    }

    @ViewBuilder private var marker: some View {
        switch kind {
        case .sensor:
            Circle().fill(PM.Colors.measuring).frame(width: 6, height: 6)
        case .arDerived:
            RoundedRectangle(cornerRadius: 1).fill(PM.Colors.accent).frame(width: 6, height: 6)
        case .userEntered:
            Circle().strokeBorder(PM.Colors.textPrimary, lineWidth: 1).frame(width: 6, height: 6)
        case .calculated:
            Text("=")
        }
    }
}

enum BadgeKind { case free, pro, locked }

/// FREE / PRO / LOCKED badges: 20 tall, 10 heavy, tracking 0.6.
struct PMBadge: View {
    var kind: BadgeKind

    var body: some View {
        HStack(spacing: 4) {
            if kind == .locked { PMIcon(.lock, size: 10, stroke: 3) }
            Text(kind == .free ? "FREE" : kind == .pro ? "PRO" : "LOCKED")
        }
        .font(.pm(10, .heavy))
        .tracking(0.6)
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(kind == .pro ? PM.Colors.badgeOutline : .clear, lineWidth: 1))
    }

    private var foreground: Color {
        switch kind {
        case .free: PM.Colors.accent
        case .pro: PM.Colors.textSecondary
        case .locked: PM.Colors.onThumb
        }
    }

    private var fill: Color {
        switch kind {
        case .free: PM.Colors.freeBadgeFill
        case .pro: .clear
        case .locked: PM.Colors.thumb
        }
    }
}

// MARK: - Segmented control

/// Pill segmented control. Level board spec: track 4 pt padding, radius 24, surface + border;
/// segments 40 tall, 13 heavy, tracking 1; selected thumb is light with dark text.
struct PMSegmented<Value: Hashable>: View {
    var options: [(value: Value, label: String)]
    @Binding var selection: Value
    var segmentHeight: CGFloat = 40
    var fontSize: CGFloat = 13
    var fontWeight: Font.Weight = .heavy
    var tracking: CGFloat = 1
    var trackFill: Color = PM.Colors.segmentTrack
    var trackBorder: Color = PM.Colors.border
    var gap: CGFloat = 4
    /// Size segments like CSS `flex-grow: 1`: each gets its label width plus an equal share of the rest.
    var fitContent = false
    /// Inset of the segments from the track's outer edge (CSS border + padding).
    var trackPadding: CGFloat = 4

    @Namespace private var ns

    var body: some View {
        let layout = fitContent ? AnyLayout(PMFlexRow(spacing: gap)) : AnyLayout(HStackLayout(spacing: gap))
        layout {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let isOn = option.value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.pm(fontSize, fontWeight))
                        .tracking(tracking)
                        .foregroundStyle(isOn ? PM.Colors.onThumb : PM.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: segmentHeight)
                        .background {
                            if isOn {
                                Capsule().fill(PM.Colors.thumb)
                                    .shadow(color: Color(dark: 0, light: 0, darkOpacity: 0, lightOpacity: 0.12), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(trackPadding)
        .background(Capsule().fill(trackFill))
        .overlay(Capsule().strokeBorder(trackBorder, lineWidth: 1))
    }
}

/// Row that gives each child its ideal width plus an equal share of the leftover (CSS `flex-grow: 1`).
struct PMFlexRow: Layout {
    var spacing: CGFloat = 0

    private func ideals(_ subviews: Subviews) -> [CGSize] { subviews.map { $0.sizeThatFits(.unspecified) } }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = ideals(subviews)
        let w = s.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: proposal.width ?? w, height: s.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let s = ideals(subviews)
        let used = s.reduce(0) { $0 + $1.width } + spacing * CGFloat(subviews.count - 1)
        let extra = (bounds.width - used) / CGFloat(subviews.count)
        var x = bounds.minX
        for (i, v) in subviews.enumerated() {
            let w = max(0, s[i].width + extra)
            v.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}

// MARK: - Readouts

/// PITCH / ROLL card: 12 bold label, 17 mono value.
struct AxisReadout: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).pmCaptionStyle(tracking: 1)
            Spacer(minLength: 4)
            Text(value)
                .font(.pmMono(17))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // CSS line box for 17 px SF Mono (normal line height), so the card is 46 tall as drawn.
                .frame(minHeight: 21.7)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .pmCard(radius: PM.Radius.cardSmall)
        .accessibilityElement(children: .combine)
    }
}

/// Signed degree formatting used by the level instruments: "+1.2°", "−0.4°", "0.0°".
func formatSignedDegrees(_ v: Double, decimals: Int = 1) -> String {
    let a = String(format: "%.\(decimals)f", abs(v))
    let zero = String(format: "%.\(decimals)f", 0.0)
    if a == zero { return a + "°" }
    return (v > 0 ? "+" : "\u{2212}") + a + "°"
}

// MARK: - Backgrounds

/// Faint 24 pt grid with the mint glow in the top-left, as on Home.
struct GridBackdrop: View {
    var showGlow = true
    var spacing: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            PM.Colors.background
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = 0
                while x <= size.width { p.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += spacing }
                var y: CGFloat = 0
                while y <= size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += spacing }
                ctx.fill(p, with: .color(PM.Colors.textPrimary.opacity(0.025)))
            }
            if showGlow {
                Circle()
                    .fill(RadialGradient(colors: [PM.Colors.accent.opacity(0.10), PM.Colors.accent.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 260))
                    .frame(width: 520, height: 520)
                    .offset(x: -120, y: -80)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Toast

struct ToastView: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            PMIcon(.check, size: 16, stroke: 2.6).foregroundStyle(PM.Colors.accent)
            Text(text).font(.pm(15, .semibold)).foregroundStyle(PM.Colors.textPrimary)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Capsule().fill(PM.Colors.surfaceRaised))
        .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }
}

// MARK: - Sheet header

/// Grabber + title + close, for bottom sheets.
struct SheetHeader: View {
    var title: String
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(PM.Colors.borderStrong).frame(width: 36, height: 5)
            HStack {
                Text(title).pmHeadlineStyle()
                Spacer()
                IconCircleButton(icon: .close, label: "Close", size: 36, iconSize: 16, stroke: 2, action: onClose)
            }
        }
    }
}

/// Safety net for fixed-design screens: on tall phones the content fills the screen exactly as designed
/// (Spacers still expand); on short phones or large text it scrolls instead of overlapping.
struct FitOrScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { g in
            ScrollView(.vertical) {
                content()
                    .frame(maxWidth: .infinity, minHeight: g.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }
}
