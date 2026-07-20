import SwiftUI
import StoreKit

// MARK: - Verdure+ Paywall
//
// Subscription tiers from the Verdure Subscription Model doc:
//   Free    — explore, map, community events, personalized discovery, Daily Gem,
//             gamification, $5–10 gift cards, basic community.
//   Verdure+ ($4.99/mo · $49.99/yr) — AI Adventure Planner, AR Adventures,
//             health integrations, premium navigation, smart outdoor insights,
//             premium rewards ($25–50 cards, multipliers), Community+, advanced
//             personalization.
// Premium Rewards gating is live today; the other Plus features ship next.

struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = StoreService.yearlyID
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.xl) {
                    hero
                    if store.isPlus {
                        memberCard
                    } else {
                        featureList
                        planPicker
                        purchaseCTA
                    }
                    footer
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .background(VerdureBackground())
            .navigationTitle("Verdure+").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                AmbientGlow(color: Palette.gold.base.opacity(0.4), size: 210, opacity: 0.8)
                MedallionHero(size: 150, interactive: false)
            }
            .frame(height: 160)
            .accessibilityHidden(true)

            KickerLabel(text: "Go further outside", color: Palette.gold.base, dot: Palette.gold.base)
            Text("Verdure+")
                .font(VType.display(38, .bold)).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Everything in free, plus the tools that turn\nwalks into adventures.")
                .font(VType.body(15)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center).lineSpacing(3)
        }
    }

    // MARK: - Active member state

    private var memberCard: some View {
        VStack(spacing: Spacing.md) {
            ClayIconTile(systemImage: "checkmark.seal.fill", kind: .teal, size: 64, radius: Radius.md)
            Text("You're a Verdure+ member")
                .font(VType.display(20, .semibold)).foregroundStyle(Palette.ink)
            Text("Premium rewards are unlocked. Manage or cancel anytime in App Store settings.")
                .font(VType.body(13)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center).lineSpacing(3)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .claySurface(.surface, radius: Radius.lg, elevation: 1.1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Features (from the subscription model doc)

    private struct PlusFeature: Identifiable {
        let icon: String
        let title: String
        let detail: String
        let kind: ClayStyle.ClayAccentKind
        let comingSoon: Bool
        var id: String { title }
    }

    private let features: [PlusFeature] = [
        PlusFeature(icon: "gift.fill", title: "Premium Rewards",
                    detail: "$25–50 gift cards, bonus multipliers & early access", kind: .gold, comingSoon: false),
        PlusFeature(icon: "wand.and.stars", title: "AI Adventure Planner",
                    detail: "Personalized itineraries for weather, time & budget", kind: .teal, comingSoon: true),
        PlusFeature(icon: "binoculars.fill", title: "AR Adventures",
                    detail: "Exclusive collectibles, seasonal quests & hidden wildlife", kind: .spruce, comingSoon: true),
        PlusFeature(icon: "heart.fill", title: "Health Integrations",
                    detail: "Apple Health sync & advanced activity insights", kind: .terracotta, comingSoon: true),
        PlusFeature(icon: "map.fill", title: "Premium Navigation",
                    detail: "Offline maps, alerts & trail guidance", kind: .sky, comingSoon: true),
        PlusFeature(icon: "chart.bar.fill", title: "Smart Outdoor Insights",
                    detail: "Crowd forecasts, best times & weather picks", kind: .teal, comingSoon: true),
        PlusFeature(icon: "person.3.fill", title: "Community+",
                    detail: "Discussions, group planning & premium clubs", kind: .spruce, comingSoon: true),
    ]

    private var featureList: some View {
        VStack(spacing: 12) {
            ForEach(features) { feature in
                HStack(spacing: Spacing.md) {
                    ClayIconTile(systemImage: feature.icon, kind: feature.kind, size: 44, radius: Radius.chip)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(feature.title)
                                .font(VType.display(15, .semibold)).foregroundStyle(Palette.ink)
                            if feature.comingSoon {
                                Text("SOON")
                                    .font(VType.body(8, .bold)).tracking(0.8)
                                    .foregroundStyle(Palette.inkSoft)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(ClayBackground(style: .inset, radius: Radius.chip))
                            }
                        }
                        Text(feature.detail)
                            .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(Spacing.md)
                .claySurface(.surface, radius: Radius.md, elevation: 0.75)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(feature.title). \(feature.detail).\(feature.comingSoon ? " Coming soon." : "")")
            }
        }
    }

    // MARK: - Plans

    private var planPicker: some View {
        HStack(spacing: 12) {
            planCard(id: StoreService.monthlyID,
                     title: "Monthly",
                     price: store.monthly?.displayPrice ?? "$4.99",
                     cadence: "per month",
                     badge: nil)
            planCard(id: StoreService.yearlyID,
                     title: "Yearly",
                     price: store.yearly?.displayPrice ?? "$49.99",
                     cadence: "per year",
                     badge: "SAVE 17%")
        }
    }

    private func planCard(id: String, title: String, price: String, cadence: String, badge: String?) -> some View {
        let isSelected = selectedID == id
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.35)) { selectedID = id }
        } label: {
            VStack(spacing: 6) {
                if let badge {
                    Text(badge)
                        .font(VType.body(9, .bold)).tracking(0.8)
                        .foregroundStyle(Palette.gold.onColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(ClayBackground(style: .accent(.gold), radius: Radius.chip, elevation: 0.3))
                } else {
                    Spacer().frame(height: 21)
                }
                Text(title).font(VType.body(13, .semibold))
                    .foregroundStyle(isSelected ? Palette.spruce.onColor : Palette.inkSoft)
                Text(price).font(VType.num(24, .bold)).monospacedDigit()
                    .foregroundStyle(isSelected ? Palette.spruce.onColor : Palette.ink)
                Text(cadence).font(VType.body(11))
                    .foregroundStyle(isSelected ? Palette.spruce.onColor.opacity(0.8) : Palette.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
        }
        .buttonStyle(ClayPressButtonStyle(
            style: isSelected ? .accent(.spruce) : .surface,
            radius: Radius.md, elevation: isSelected ? 1.0 : 0.7))
        .accessibilityLabel("\(title) plan, \(price) \(cadence)\(badge != nil ? ", best value" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - CTA

    private var selectedProduct: Product? {
        selectedID == StoreService.yearlyID ? store.yearly : store.monthly
    }

    private var purchaseCTA: some View {
        VStack(spacing: Spacing.sm) {
            if store.products.isEmpty && !store.isLoadingProducts {
                Text("Subscriptions aren't available right now. In the simulator, run the Verdure scheme (it loads Verdure.storekit); on device this needs App Store Connect products.")
                    .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(Spacing.md)
                    .background(ClayBackground(style: .inset, radius: Radius.sm))
            }

            ClayButton(isWorking ? "One moment…" : "Start Verdure+",
                       systemImage: "sparkles", kind: .spruce, fullWidth: true) {
                guard let product = selectedProduct, !isWorking else { return }
                isWorking = true
                Task {
                    let purchased = await store.purchase(product)
                    isWorking = false
                    if purchased {
                        AccessibilityNotification.Announcement("Welcome to Verdure Plus.").post()
                    }
                }
            }
            .disabled(selectedProduct == nil || isWorking)
            .opacity(selectedProduct == nil || isWorking ? 0.6 : 1)
            .accessibilityLabel("Start Verdure Plus")
            .accessibilityHint("Subscribes to the selected plan.")

            Button {
                guard !isWorking else { return }
                isWorking = true
                Task { await store.restorePurchases(); isWorking = false }
            } label: {
                Text("Restore Purchases")
                    .font(VType.body(13, .semibold)).foregroundStyle(Palette.spruce.base)
            }
            .buttonStyle(.plain)

            if let error = store.lastError {
                Text(error)
                    .font(VType.body(12, .medium)).foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footer: some View {
        Text("Auto-renews until cancelled. Manage in App Store settings.\nPrices shown in your local currency at checkout.")
            .font(VType.body(11)).foregroundStyle(Palette.inkFaint)
            .multilineTextAlignment(.center).lineSpacing(2)
    }
}

#Preview {
    PaywallView()
        .environment(StoreService())
}
