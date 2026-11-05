//
//  RootView.swift
//  Plumb
//

import SwiftUI

struct RootView: View {
    @State private var router = Router()
    @State private var store = MeasurementStore.shared
    @State private var settings = AppSettings.shared
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var debugOnboarding = false

    var body: some View {
        NavigationStack(path: $router.path) {
            ZStack(alignment: .bottom) {
                Group {
                    switch router.tab {
                    case .home: HomeView()
                    case .tools: ToolsView()
                    case .projects: ProjectsView()
                    case .history: HistoryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                PMTabBar(selection: Binding(get: { router.tab }, set: { router.tab = $0 }))
            }
            .background(PM.Colors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                route.destination
                    .toolbar(.hidden, for: .navigationBar)
                    .background(PM.Colors.background.ignoresSafeArea())
            }
        }
        .environment(router)
        .environment(store)
        .environment(settings)
        .tint(PM.Colors.accent)
        .fullScreenCover(isPresented: Binding(
            get: { DebugLaunch.isActive ? debugOnboarding : !hasOnboarded },
            set: { hasOnboarded = !$0; debugOnboarding = $0 }
        )) {
            OnboardingView { hasOnboarded = true; debugOnboarding = false }
                .environment(router)
                .environment(settings)
        }
        .preferredColorScheme(DebugLaunch.colorScheme)
        // Settings > Reduce Motion on: every animation becomes the 200 ms cross-fade from tokens.json
        // (this also stops repeating loops such as hovering illustrations).
        .transaction { t in
            if settings.reduceMotionOverride == true, t.animation != nil { t.animation = .easeInOut(duration: 0.2) }
        }
        .task {
            debugOnboarding = DebugLaunch.apply(to: router, store: store)
            await ProStore.shared.start()
        }
    }
}

/// Keeps the phone-sized layouts (and the hand-drawn scenes, which are drawn for ~390 pt) at a phone-like
/// width on iPad and other wide windows, centred, instead of stretching them across the screen.
struct PhoneColumn<Content: View>: View {
    static var maxWidth: CGFloat { 600 }
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            content()
                .frame(width: min(geo.size.width, Self.maxWidth), height: geo.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PM.Colors.background.ignoresSafeArea())
    }
}

/// Custom tab bar from the Home board: 88 tall including the home indicator,
/// padding 10 / 12 / 26, 92% background, 1 pt top rule. Selected item accent + 700, others secondary + 600.
struct PMTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // LightMode board: 84 tall, padding 8 / 12 / 24, 3 pt icon gap. Dark: 88, 10 / 12 / 26, 4.
        let light = colorScheme == .light
        GeometryReader { geo in
            let bottomInset = geo.safeAreaInsets.bottom
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    let on = tab == selection
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: light ? 3 : 4) {
                            PMIcon(tab.icon, size: 24, stroke: on ? 1.9 : 1.7)
                            Text(tab.title).font(.pm(12, on ? .bold : .semibold))
                        }
                        .foregroundStyle(on ? PM.Colors.accent : PM.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityLabel(tab.title)
                    .accessibilityHint(on ? "" : "Switch to \(tab.title)")
                }
            }
            .frame(height: 51)
            .padding(.horizontal, 12)
            .padding(.top, light ? 9 : 11) // 1 pt top rule + board padding
            .frame(maxWidth: .infinity)
            .frame(height: (light ? 84 : 88) - (bottomInset > 0 ? 0 : 16), alignment: .top)
            .background(Color(dark: 0x0B0D0F, light: 0xFFFFFF))
            
            .overlay(alignment: .top) { PM.Colors.divider.frame(height: 1) }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .frame(height: light ? PMTabBar.visibleHeight - 4 : PMTabBar.visibleHeight)
    }

    /// Height above the home indicator. Scroll views on tab screens should add this as bottom content margin.
    static let visibleHeight: CGFloat = 88 - PM.Board.homeIndicator
}
