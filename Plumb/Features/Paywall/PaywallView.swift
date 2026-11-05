//
//  PaywallView.swift
//  Plumb
//
//  Pro board. Prices come from StoreKit; a spinner shows while they load.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    @State private var plan: PaywallPlan = .annual
    @State private var store = ProStore.shared
    @State private var busy = false
    @State private var message: PaywallMessage?

    private let benefits = ["AR Measure", "Room Measure", "Photo Measure", "Projects", "PDF Reports",
                            "Advanced Calculators", "Measurement History"]

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 10) {
                    PaywallIconCluster()
                        .padding(.top, 44) // clears the close button

                    VStack(spacing: 6) {
                        WrapText("Unlock the Complete Toolkit", size: 28, weight: .bold, tracking: -0.5,
                                 alignment: .center, color: PM.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("The Bubble Level and core tools stay free.")
                            .font(.pm(14))
                            .foregroundStyle(PM.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .leading),
                                        GridItem(.flexible(), spacing: 12, alignment: .leading)],
                              alignment: .leading, spacing: 9) {
                        ForEach(benefits, id: \.self) { b in
                            HStack(spacing: 8) {
                                PMIcon(.check, size: 16, stroke: 2.6).foregroundStyle(PM.Colors.accent)
                                Text(b)
                                    .font(.pm(14, .medium))
                                    .foregroundStyle(PM.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, 15)
                    .padding(.horizontal, 17)
                    .pmCard(radius: 22)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Pro includes")

                    VStack(spacing: 8) {
                        ForEach(PaywallPlan.allCases, id: \.self) { p in
                            PaywallPlanCard(plan: p, price: store.priceText(p), loading: !store.didLoad, isOn: p == plan) {
                                withAnimation(.easeOut(duration: 0.2)) { plan = p }
                                Haptics.selection()
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Plan")

                    WrapText(plan.terms, size: 12, lineHeight: 1.45, alignment: .center, color: PM.Colors.textSecondary)

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        Button(action: continueTapped) {
                            if busy {
                                ProgressView().tint(PM.Colors.onAccent)
                            } else {
                                Text(settings.isPro ? "Pro is active" : "Continue")
                            }
                        }
                        .buttonStyle(.pmPrimary)
                        .disabled(busy)
                        .accessibilityHint(settings.isPro ? "Closes this screen" : "Buys \(plan.name) Pro")

                        Button { router.pop() } label: {
                            Text("Maybe later")
                                .font(.pm(16, .semibold))
                                .foregroundStyle(PM.Colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Capsule().fill(PM.Colors.surface))
                                .overlay(Capsule().strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pmPress)
                    }

                    HStack(spacing: 18) {
                        footerLink("Restore Purchases") { restore() }
                        footerLink("Terms") {
                            // Apple's standard licence agreement until a custom EULA exists.
                            if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                                openURL(url)
                            }
                        }
                        footerLink("Privacy") { message = .privacy }
                    }
                }
                .padding(.top, 50 - PM.Board.statusBar)
                .padding(.horizontal, PM.Space.gutter)
                .padding(.bottom, 16)
                .frame(minHeight: geo.size.height + geo.safeAreaInsets.bottom)
                .overlay(alignment: .topLeading) {
                    IconCircleButton(icon: .close, label: "Close", iconSize: 18, stroke: 2.2) { router.pop() }
                        .padding(.top, 50 + 1 - PM.Board.statusBar)
                        .padding(.leading, PM.Space.gutter + 1)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .bottom)
        }
        .background(PM.Colors.background.ignoresSafeArea())
        .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
               presenting: message) { m in
            switch m {
            case .purchased, .restored:
                Button("Done") { router.pop() }
            case .unavailable:
                #if DEBUG
                Button("Unlock Pro (debug build)") {
                    settings.isPro = true
                    router.pop()
                }
                #endif
                Button("OK", role: .cancel) {}
            default:
                Button("OK", role: .cancel) {}
            }
        } message: { m in
            Text(m.body)
        }
        .task { await store.loadProductsIfNeeded() }
    }

    private func continueTapped() {
        guard !settings.isPro else { router.pop(); return }
        busy = true
        Task {
            let outcome = await store.purchase(plan)
            busy = false
            switch outcome {
            case .purchased:
                Haptics.measurementSaved()
                message = .purchased
            case .cancelled:
                break
            case .pending:
                message = .pending
            case .unavailable:
                message = .unavailable
            case .failed(let why):
                message = .failed(why)
            }
        }
    }

    private func restore() {
        guard !busy else { return }
        busy = true
        Task {
            let outcome = await store.restore()
            busy = false
            message = outcome
        }
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.pm(13))
                .underline()
                .foregroundStyle(PM.Colors.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum PaywallPlan: CaseIterable {
    case annual, lifetime

    var name: String { self == .annual ? "Annual" : "Lifetime" }
    var detail: String { self == .annual ? "Billed once a year" : "Pay once, keep Pro forever" }
    var productID: String { self == .annual ? ProStore.annualID : ProStore.lifetimeID }
    var terms: String {
        self == .annual
            ? "Annual renews each year until you cancel in Settings. Cancel anytime."
            : "Lifetime is a one-time purchase. No renewal."
    }
}

/// Alerts shown by the paywall and by Settings > Restore Purchases.
enum PaywallMessage: Hashable {
    case purchased, restored, nothingToRestore, pending, unavailable, privacy
    case failed(String)

    var title: String {
        switch self {
        case .purchased: "Welcome to Pro"
        case .restored: "Purchases restored"
        case .nothingToRestore: "Nothing to restore"
        case .pending: "Purchase pending"
        case .unavailable: "Purchases unavailable"
        case .privacy: "Privacy"
        case .failed: "Purchase didn\u{2019}t go through"
        }
    }

    var body: String {
        switch self {
        case .purchased: "Every tool is unlocked on this \(Device.name)."
        case .restored: "Pro is active again on this \(Device.name)."
        case .nothingToRestore: "No Pro purchase was found for this Apple Account."
        case .pending: "Your purchase is waiting for approval. Pro unlocks as soon as it\u{2019}s approved."
        case .unavailable: "The App Store isn\u{2019}t available right now. Check your connection and try again."
        case .privacy: "Measurements, photos and reports stay on this \(Device.name) unless you share them. Plumb has no account, no analytics and no ads."
        case .failed(let why): why
        }
    }
}

// MARK: - StoreKit

/// StoreKit 2 purchases for Pro. Product IDs must match App Store Connect.
@Observable
final class ProStore {
    static let shared = ProStore()
    static let annualID = "com.kinwild.plimb.pro.annual"
    static let lifetimeID = "com.kinwild.plimb.pro.lifetime"
    private static let ids: Set<String> = [annualID, lifetimeID]

    enum PurchaseOutcome { case purchased, cancelled, pending, unavailable, failed(String) }

    private(set) var products: [String: Product] = [:]
    /// True once a product request has finished, whether or not it returned products.
    private(set) var didLoad = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var updates: Task<Void, Never>?

    /// Starts listening for transactions (Ask to Buy approvals, renewals, refunds) and refreshes Pro.
    func start() async {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlements()
            }
        }
        await loadProductsIfNeeded()
        await refreshEntitlements()
    }

    func loadProductsIfNeeded() async {
        guard products.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        if let list = try? await Product.products(for: Self.ids) {
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        }
        didLoad = true
    }

    /// Nil until StoreKit returns the product's display price.
    func priceText(_ plan: PaywallPlan) -> String? {
        guard let p = products[plan.productID] else { return nil }
        return plan == .annual ? "\(p.displayPrice)/year" : p.displayPrice
    }

    func purchase(_ plan: PaywallPlan) async -> PurchaseOutcome {
        await loadProductsIfNeeded()
        guard let product = products[plan.productID] else { return .unavailable }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else {
                    return .failed("The App Store couldn\u{2019}t verify this purchase. You haven\u{2019}t been charged twice; try Restore Purchases.")
                }
                await t.finish()
                AppSettings.shared.isPro = true
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async -> PaywallMessage {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .nothingToRestore
        } catch {
            return .unavailable
        }
        let has = await hasEntitlement()
        if has { AppSettings.shared.isPro = true }
        return has ? .restored : .nothingToRestore
    }

    /// Grants Pro for a verified, unrevoked entitlement. Only removes Pro when the App Store answered
    /// with our products (so an offline launch never locks a paying user out).
    func refreshEntitlements() async {
        let has = await hasEntitlement()
        if has {
            AppSettings.shared.isPro = true
        } else if !products.isEmpty {
            AppSettings.shared.isPro = false
        }
    }

    private func hasEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.ids.contains(t.productID), t.revocationDate == nil {
                if let exp = t.expirationDate, exp < Date() { continue }
                return true
            }
        }
        return false
    }
}

/// Radio-style plan card: 2 pt border, accent and tinted fill when selected.
struct PaywallPlanCard: View {
    var plan: PaywallPlan
    var price: String?
    var loading: Bool
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    if isOn {
                        Circle().fill(PM.Colors.background)
                        Circle().strokeBorder(PM.Colors.accent, lineWidth: 6)
                    } else {
                        Circle().strokeBorder(PM.Colors.unavailable, lineWidth: 2)
                    }
                }
                .frame(width: 20, height: 20)

                FlexShrinkRow(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name).font(.pm(16, .bold)).foregroundStyle(PM.Colors.textPrimary)
                        WrapText(plan.detail, size: 13, color: PM.Colors.textSecondary)
                    }
                    if let price {
                        WrapText(price, size: 15, weight: .bold, alignment: .center, color: PM.Colors.textPrimary,
                                 monospacedDigits: true)
                    } else if loading {
                        ProgressView().tint(PM.Colors.textSecondary)
                    } else {
                        Text("Price unavailable")
                            .font(.pm(13, .medium))
                            .foregroundStyle(PM.Colors.textSecondary)
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isOn ? PM.Colors.recommendedFill : PM.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isOn ? PM.Colors.accent : PM.Colors.border, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plan.name), \(plan.detail), \(price ?? (loading ? "Loading price" : "Price unavailable"))")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// CSS flexbox for two items: the first grows into spare room; when they don't fit, both shrink in
/// proportion to their natural widths (never below their longest word), so text wraps like the board.
struct FlexShrinkRow: Layout {
    var spacing: CGFloat = 12

    private func widths(_ subviews: Subviews, _ width: CGFloat) -> [CGFloat] {
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }
        let minimum = subviews.map { $0.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width }
        let avail = max(0, width - spacing * CGFloat(max(0, subviews.count - 1)))
        let total = natural.reduce(0, +)
        guard total > avail, total > 0 else {
            var w = natural
            if !w.isEmpty { w[0] += avail - total }
            return w
        }
        let over = total - avail
        var w = zip(natural, minimum).map { n, m in max(m, n - over * n / total) }
        let excess = w.reduce(0, +) - avail
        if excess > 0, let i = w.indices.max(by: { w[$0] - minimum[$0] < w[$1] - minimum[$1] }) {
            w[i] = max(minimum[i], w[i] - excess)
        }
        return w
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
            + spacing * CGFloat(max(0, subviews.count - 1))
        let w = widths(subviews, width)
        let h = zip(subviews, w).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(subviews, bounds.width)
        var x = bounds.minX
        for (v, wi) in zip(subviews, w) {
            let size = v.sizeThatFits(ProposedViewSize(width: wi, height: nil))
            v.place(at: CGPoint(x: x, y: bounds.midY - size.height / 2), proposal: ProposedViewSize(width: wi, height: size.height))
            x += wi + spacing
        }
    }
}

/// Floating tool tiles above the title; the four outer tiles bob 4 pt on staggered 4 s loops.
struct PaywallIconCluster: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    private struct Tile {
        var x: CGFloat, y: CGFloat, size: CGFloat, radius: CGFloat
        var d: String, iconSize: CGFloat, tint: Color, delay: Double
    }

    private var tiles: [Tile] {
        [
            Tile(x: 44, y: 34, size: 48, radius: 16, d: PMIconName.room.d, iconSize: 22, tint: PM.Colors.textSecondary, delay: 0),
            Tile(x: 104, y: 10, size: 54, radius: 18, d: PMIconName.ar.d, iconSize: 24, tint: PM.Colors.measuring, delay: 0.6),
            Tile(x: 240, y: 12, size: 54, radius: 18, d: PMIconName.photoMarkers.d, iconSize: 24, tint: PM.Colors.textSecondary, delay: 1.2),
            Tile(x: 302, y: 36, size: 44, radius: 15, d: PMIconName.document.d, iconSize: 20, tint: PM.Colors.textSecondary, delay: 1.8),
        ]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(tiles.indices, id: \.self) { i in
                let t = tiles[i]
                SVGStroke(d: t.d, size: t.iconSize, lineWidth: 1.7)
                    .foregroundStyle(t.tint)
                    .frame(width: t.size, height: t.size)
                    .pmCard(radius: t.radius)
                    .offset(x: t.x, y: t.y + (up ? -4 : 0))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true).delay(t.delay), value: up)
            }
            PMIcon(.level, size: 30, stroke: 1.8)
                .foregroundStyle(PM.Colors.onAccent)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(PM.Colors.accent))
                .offset(x: 167, y: 0)
        }
        .frame(width: 350, height: 92, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear { up = true }
    }
}
