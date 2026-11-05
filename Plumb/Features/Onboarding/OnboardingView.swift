//
//  OnboardingView.swift
//  Plumb
//
//  Four onboarding screens (Onboarding board). Positions are the board's, measured from the
//  top of the 390 x 844 frame; the controls stay anchored 40 pt above the bottom edge. On shorter
//  phones the art and gaps shrink so the text always ends above the controls.
//

import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(Router.self) private var router
    @State private var page = min(3, max(0, Int(DebugLaunch.state ?? "") ?? 0))
    /// Height of the bottom controls (dots, button, and the last page's note); pages end above them.
    @State private var controlsHeight: CGFloat = 78
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [OnboardingPage] = [
        .init(title: "Measure Anything.", body: "A live level, angle finder, ruler and compass, driven by your \(Device.name)’s real sensors.", art: .level),
        .init(title: "Know Your Angle.", body: "Absolute or relative angles, shown only as precisely as your \(Device.name) can measure.", art: .angle),
        .init(title: "Measure Your Space.", body: "Point-to-point distances and room outlines with AR, where your \(Device.name) supports it.", art: .space),
        .init(title: "Your Tools. One App.", body: "Save measurements to projects and share clean PDF reports.", art: .tools),
    ]

    private var isLast: Bool { page == pages.count - 1 }

    private static let controlsBottom: CGFloat = 35

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    OnboardingPageView(page: pages[i], isActive: page == i,
                                       bottomInset: Self.controlsBottom + controlsHeight)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Skip: top 56, right 20.
            HStack {
                Spacer()
                if !isLast {
                    Button("Skip", action: onFinish)
                        .font(.pm(15, .semibold))
                        .foregroundStyle(PM.Colors.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityHint("Skip the introduction")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 9) // board: 20 + 1 pt border, minus the 12 pt hit padding
            .padding(.top, 57.5) // board 56; +1.5 baseline compensation
            .ignoresSafeArea()

            controls
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                .frame(maxWidth: sizeClass == .regular ? 520 : .infinity)
                .padding(.horizontal, 21) // board: 20 inside the 1 pt phone border
                .padding(.bottom, sizeClass == .regular ? 56 : Self.controlsBottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Glow: 510 pt at (-60, 90) on the frame. Drawn as an overlay of the background so its
        // size never widens the layout.
        .background {
            PM.Colors.background
                .overlay(alignment: sizeClass == .regular ? .center : .topLeading) {
                    Circle()
                        .fill(RadialGradient(colors: [PM.Colors.accent.opacity(0.09), PM.Colors.accent.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: 255))
                        .frame(width: 510, height: 510)
                        .offset(x: sizeClass == .regular ? 0 : -60, y: sizeClass == .regular ? -60 : 90)
                        .scaleEffect(sizeClass == .regular ? 1.8 : 1)
                }
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        // Onboarding is designed in the dark instrument theme only.
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .animation(PM.Motion.normal, value: page)
        // Auto-advance: every few seconds, with a slow ease between pages. Any swipe or tap changes `page`,
        // which restarts this task, so the timer never fights the user. Stops on the last page; off with
        // Reduce Motion and for debug screenshots.
        .task(id: page) {
            guard !reduceMotion, !DebugLaunch.isActive, page < pages.count - 1 else { return }
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.7)) { page += 1 }
        }
    }

    private var controls: some View {
        VStack(alignment: sizeClass == .regular ? .center : .leading, spacing: 18) {
            if isLast {
                if sizeClass == .regular {
                    Text("We'll ask for camera or location only when a tool needs it.")
                        .font(.pm(15)).foregroundStyle(PM.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    BoardWrapText("We'll ask for camera or location only when a tool needs it.", size: 13, tracking: -0.05, lineHeight: 1.4,
                                  color: PM.Colors.textSecondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { j in
                    Capsule()
                        .fill(j == page ? PM.Colors.accent : PM.Colors.tickMinor)
                        .frame(width: j == page ? 22 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: sizeClass == .regular ? .center : .leading)
            .accessibilityElement()
            .accessibilityLabel("Step \(page + 1) of \(pages.count)")

            if isLast {
                Button("Start Measuring") {
                    // Straight into the level, the app's core tool.
                    router.select(.home)
                    router.push(.level)
                    onFinish()
                }
                .buttonStyle(PMPrimaryButtonStyle(height: 54))
            } else {
                Button("Continue") { page = min(page + 1, pages.count - 1) }
                    .buttonStyle(PMSecondaryButtonStyle(height: 54, fontSize: 17, fillWidth: true))
                    .accessibilityHint("Next of \(pages.count) screens")
            }
        }
    }
}

// MARK: - Page

private struct OnboardingPage {
    enum Art { case level, angle, space, tools }
    var title: String
    var body: String
    var art: Art
}

private struct OnboardingPageView: View {
    var page: OnboardingPage
    var isActive: Bool
    /// Space taken by the pinned controls, from the bottom of the frame.
    var bottomInset: CGFloat

    @State private var textHeight: CGFloat = 130
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Board: art 300 pt square at y 150, text at y 500 (+1.5 baseline compensation).
    private static let art: CGFloat = 300

    @ViewBuilder private var artView: some View {
        switch page.art {
        case .level: OnboardingLevelArt()
        case .angle: OnboardingAngleArt()
        case .space: OnboardingSpaceArt()
        case .tools: OnboardingToolsArt()
        }
    }

    /// iPad and other wide windows: everything centred as one column, art scaled up to use the height,
    /// text centred under it with a comfortable line length. Phone layout below is untouched.
    private var wideBody: some View {
        GeometryReader { g in
            let available = g.size.height - bottomInset - 120 - 150
            let k = min(2.2, max(0.8, available / Self.art))
            VStack(spacing: 0) {
                Spacer(minLength: 100)
                artView
                    .frame(width: Self.art, height: Self.art, alignment: .topLeading)
                    .scaleEffect(k, anchor: .topLeading)
                    .frame(width: Self.art * k, height: Self.art * k, alignment: .topLeading)
                    .accessibilityHidden(true)
                VStack(spacing: 16) {
                    Text(page.title)
                        .font(.pm(52, .bold)).tracking(-1.2)
                        .foregroundStyle(PM.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(page.body)
                        .font(.pm(23))
                        .lineSpacing(5)
                        .foregroundStyle(PM.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 32)
                .padding(.top, 36)
                .accessibilityElement(children: .combine)
                Spacer(minLength: bottomInset + 24)
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
    }

    var body: some View {
        if sizeClass == .regular { wideBody } else { phoneBody }
    }

    private var phoneBody: some View {
        GeometryReader { g in
            let h = g.size.height
            // 0 on the shortest phones (667 pt, iPhone SE), 1 from the 844 pt board up.
            let t = min(1, max(0, (h - 667) / (844 - 667)))
            let artTop = 106 + 44 * t // stays below the Skip button (y 57.5...101.5)
            let gap = 24 + 26 * t // board: 50 below the art
            let room = h - bottomInset - 16 - artTop - gap - textHeight
            let k = min(1, max(0.5, room / Self.art))

            // Fits without scrolling on every iPhone; scrolls only if the text can't fit at all.
            FitOrScroll {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        switch page.art {
                        case .level: OnboardingLevelArt()
                        case .angle: OnboardingAngleArt()
                        case .space: OnboardingSpaceArt()
                        case .tools: OnboardingToolsArt()
                        }
                    }
                    .frame(width: Self.art, height: Self.art, alignment: .topLeading)
                    .scaleEffect(k, anchor: .topLeading)
                    .frame(width: Self.art * k, height: Self.art * k, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                    .padding(.top, artTop)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(page.title)
                            .font(.pm(34, .bold)).tracking(-0.8)
                            .foregroundStyle(PM.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        BoardWrapText(page.body, size: 17, lineHeight: 1.45, color: PM.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 21)
                    .padding(.top, 1.5) // CoreText vs WebKit baseline
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                    .padding(.top, gap)
                    .accessibilityElement(children: .combine)
                }
                // Content ends above the pinned dots and button.
                .padding(.bottom, bottomInset + 16)
            }
            .ignoresSafeArea()
        }
        // Board positions are from the frame top, not the safe area.
        .ignoresSafeArea()
    }
}

// MARK: - Illustrations (300 x 300, board coordinates)

private struct OnboardingLevelArt: View {
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(RadialGradient(stops: [.init(color: PM.Colors.dialFaceTop, location: 0),
                                             .init(color: PM.Colors.dialFaceBottom, location: 0.7)],
                                     center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 207))
                .overlay(Circle().strokeBorder(PM.Colors.dialRim, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 25, y: 20)
                .frame(width: 260, height: 260)
                .offset(x: 20, y: 20)
            Circle().strokeBorder(PM.Colors.dialLine, lineWidth: 1)
                .frame(width: 178, height: 178).offset(x: 60, y: 60)
            Rectangle().fill(PM.Colors.dialLine).frame(width: 1, height: 200).offset(x: 150, y: 50)
            Rectangle().fill(PM.Colors.dialLine).frame(width: 200, height: 1).offset(x: 50, y: 150)
            Circle().strokeBorder(PM.Colors.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 52, height: 52).offset(x: 124, y: 124)
            LevelBubble(style: .classic, isPerfect: false, diameter: 42)
                .shadow(color: PM.Colors.accent.opacity(0.45), radius: 14)
                .offset(x: 129 + (drift ? 22 : -26), y: 129 + (drift ? -6 : 8))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

private struct OnboardingAngleArt: View {
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingHalfDisc()
                .fill(RadialGradient(stops: [.init(color: Color(dark: 0x1A2126, light: 0xFFFFFF), location: 0),
                                             .init(color: PM.Colors.dialFaceBottom, location: 0.7)],
                                     center: .bottom, startRadius: 0, endRadius: 198))
                .overlay(OnboardingHalfDisc(closed: false).stroke(PM.Colors.dialRim, lineWidth: 1))
                .frame(width: 280, height: 140)
                .offset(x: 10, y: 40)

            Canvas { ctx, _ in
                for k in 0...18 {
                    let major = k % 3 == 0
                    let w: CGFloat = major ? 2 : 1
                    let h: CGFloat = major ? 12 : 7
                    var t = ctx
                    t.translateBy(x: 150, y: 180)
                    t.rotate(by: .degrees(Double(-90 + k * 10)))
                    t.fill(Path(CGRect(x: -w / 2, y: -136, width: w, height: h)),
                           with: .color(major ? PM.Colors.tickMajor : PM.Colors.tickMinor))
                }
            }
            .frame(width: 300, height: 300)

            RoundedRectangle(cornerRadius: 1)
                .fill(PM.Colors.accent)
                .frame(width: 2, height: 120)
                .shadow(color: PM.Colors.accent.opacity(0.6), radius: 5)
                .rotationEffect(.degrees(sweep ? -20 : -58), anchor: .bottom)
                .offset(x: 149, y: 60)

            Circle().fill(PM.Colors.textPrimary).frame(width: 16, height: 16).offset(x: 142, y: 172)

            Text("37.2°")
                .font(.system(size: 48, weight: .light))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                .frame(width: 300)
                .offset(y: 214)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { sweep = true }
        }
    }
}

/// Top half of a circle filling its frame (`border-radius: 140px 140px 0 0`).
private struct OnboardingHalfDisc: Shape {
    var closed = true

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.maxY), radius: rect.width / 2,
                 startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        if closed { p.closeSubpath() }
        return p
    }
}

private struct OnboardingSpaceArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Floor grid: 260 x 200 at (20, 110), rotateX(62deg) from its bottom edge, perspective 600.
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(PM.Colors.accent.opacity(0.05)))
                var lines = Path()
                var y: CGFloat = 0
                while y < size.height { lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 26 }
                var x: CGFloat = 0
                while x < size.width { lines.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 26 }
                ctx.fill(lines, with: .color(PM.Colors.accent.opacity(0.35)))
                ctx.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)),
                           with: .color(PM.Colors.accent.opacity(0.5)), lineWidth: 1)
            }
            .frame(width: 260, height: 200)
            .levelCSSProjection(size: CGSize(width: 260, height: 200), origin: CGPoint(x: 130, y: 200),
                                transforms: [.rotateX(62)],
                                perspectiveOrigin: CGPoint(x: 130, y: 40), distance: 600)
            .offset(x: 20, y: 110)

            // Wall outline, open at the bottom.
            Path { p in
                p.move(to: CGPoint(x: 0.5, y: 150)); p.addLine(to: CGPoint(x: 0.5, y: 0.5))
                p.addLine(to: CGPoint(x: 211.5, y: 0.5)); p.addLine(to: CGPoint(x: 211.5, y: 150))
            }
            .stroke(PM.Colors.badgeOutline, lineWidth: 1)
            .frame(width: 212, height: 150)
            .offset(x: 44, y: 70)

            bracket(rotation: 0).offset(x: 36, y: 62)
            bracket(rotation: 90).offset(x: 248, y: 62)
            bracket(rotation: 270).offset(x: 36, y: 212)
            bracket(rotation: 180).offset(x: 248, y: 212)

            if !reduceMotion {
                TimelineView(.animation) { tl in
                    let phase = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6) / 3.6
                    LinearGradient(colors: [PM.Colors.measuring.opacity(0), PM.Colors.measuring, PM.Colors.measuring.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 260, height: 2)
                        .opacity(phase < 0.2 ? phase / 0.2 : 1 - (phase - 0.2) / 0.8)
                        .offset(x: 20, y: 10 + 240 * phase)
                }
            }

            Text("4.82 m × 3.71 m")
                .font(.pm(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(PM.Colors.textPrimary)
                // CSS content-box: 28 tall + 10 padding, plus the 1 pt border outside.
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(Capsule().fill(PM.Colors.surface))
                .overlay(Capsule().strokeBorder(PM.Colors.border, lineWidth: 1))
                .offset(x: 90, y: 244)
        }
    }

    /// 16 pt corner bracket, 2 pt stroke; rotation picks the corner (0 = top-left).
    private func bracket(rotation: Double) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 1, y: 16)); p.addLine(to: CGPoint(x: 1, y: 1)); p.addLine(to: CGPoint(x: 16, y: 1))
        }
        .stroke(PM.Colors.textPrimary, lineWidth: 2)
        .frame(width: 16, height: 16)
        .rotationEffect(.degrees(rotation))
    }
}

private struct OnboardingToolsArt: View {
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let icons: [String] = [
        "M4 20h16 M4 20L17 6 M11 20a7 7 0 0 0-2.1-5",
        "M4 7h16a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M6 7v4M10 7v3M14 7v4M18 7v3",
        "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0 M15.5 8.5l-2 5-5 2 2-5z",
        "M12 3l8 4.5v9L12 21l-8-4.5v-9z M12 12l8-4.5M12 12v9M12 12L4 7.5",
        "M4 4h16v16H4z M4 12h7v8M15 4v5",
        "M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z M7 15l10-6",
        "M3 17a9 9 0 0 1 18 0z M12 17l4-6",
        "M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M8 7h8M8 11h2M14 11h2M8 15h2M14 15h2",
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle().strokeBorder(PM.Colors.dialLine, lineWidth: 1).frame(width: 100, height: 100).offset(x: 100, y: 100)
            Circle().strokeBorder(Color(dark: 0x1F262B, light: 0xE2E5E1), lineWidth: 1).frame(width: 200, height: 200).offset(x: 50, y: 50)
            Circle().strokeBorder(Color(dark: 0x1A2024, light: 0xE8EBE7), lineWidth: 1).frame(width: 300, height: 300)

            PMIcon(.levelPlain, size: 26, stroke: 1.9)
                .foregroundStyle(PM.Colors.onAccent)
                .frame(width: 56, height: 56)
                .background(Circle().fill(PM.Colors.accent))
                .offset(x: 122, y: 122)

            ZStack(alignment: .topLeading) {
                ForEach(icons.indices, id: \.self) { n in
                    let r: CGFloat = n % 2 == 0 ? 100 : 150
                    let a = Double(n * 45 + 20) * .pi / 180
                    SVGStroke(d: icons[n], size: 20, lineWidth: 1.7)
                        .foregroundStyle(PM.Colors.accent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(PM.Colors.surface))
                        .overlay(Circle().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                        .offset(x: 150 + r * cos(a) - 20, y: 150 + r * sin(a) - 20)
                }
            }
            .frame(width: 300, height: 300, alignment: .topLeading)
            .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

#Preview {
    OnboardingView {}
}
