import SwiftUI

struct RewardsStoreView: View {
    @Environment(GameStateManager.self) private var gameState
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReward: Reward? = nil
    @State private var redeemedReward: Reward? = nil
    @State private var redeemError: String? = nil
    @State private var isRedeeming = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.xl) {
                    balanceHeader
                    ForEach(RewardTier.allCases) { tier in
                        let tierRewards = SampleData.rewards.filter { $0.tier == tier }
                        if !tierRewards.isEmpty { rewardSection(tier: tier, rewards: tierRewards) }
                    }
                }
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .background(VerdureBackground())
            .navigationTitle("Rewards").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(VType.body(15, .semibold)).foregroundStyle(Palette.spruce.base)
                }
            }
            .alert("Redeem Reward?", isPresented: Binding(
                get: { confirmingReward != nil },
                set: { if !$0 { confirmingReward = nil } }
            )) {
                Button("Cancel", role: .cancel) { confirmingReward = nil }
                Button("Redeem") {
                    if let reward = confirmingReward {
                        confirmingReward = nil
                        redeem(reward)
                    }
                }
            } message: {
                if let reward = confirmingReward { Text("Spend \(reward.pointCost) points on \(reward.name)?") }
            }
            .alert("Couldn't Redeem", isPresented: Binding(
                get: { redeemError != nil },
                set: { if !$0 { redeemError = nil } }
            )) {
                Button("OK") { redeemError = nil }
            } message: {
                if let msg = redeemError { Text(msg) }
            }
            .sheet(item: $redeemedReward) { reward in
                RewardConfirmationView(reward: reward)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
    }

    /// Server-authoritative redemption: the Cloud Function deducts points and marks
    /// the reward redeemed atomically; rapid double-taps are blocked locally AND
    /// idempotent on the server.
    private func redeem(_ reward: Reward) {
        guard !isRedeeming else { return }
        isRedeeming = true
        Task {
            defer { isRedeeming = false }
            switch await gameState.redeemReward(reward) {
            case .success:
                Haptics.success()
                AccessibilityNotification.Announcement("Redeemed \(reward.name).").post()
                redeemedReward = reward
            case .alreadyRedeemed:
                redeemError = "You've already redeemed this reward."
            case .notEnoughPoints:
                redeemError = "Not enough points yet — attend more events to earn more."
            case .offline:
                redeemError = "You're offline. Connect to the internet to redeem rewards."
            case .failed(let message):
                redeemError = message
            }
        }
    }

    // MARK: - Verdure+ gating
    //
    // Free tier redeems $5–10 cards (Bronze/Silver). Higher-value cards
    // (Gold/Platinum) are part of Verdure+ Premium Rewards.

    private func isTierLocked(_ tier: RewardTier) -> Bool {
        (tier == .gold || tier == .platinum) && !store.isPlus
    }

    // MARK: - Balance header (evergreen clay)

    private var balanceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("AVAILABLE POINTS").font(VType.body(10, .bold)).tracking(1.6)
                    .foregroundStyle(Palette.gold.base.opacity(0.9))
                Text("\(gameState.pointsBalance)")
                    .font(VType.num(40, .bold)).monospacedDigit()
                    .foregroundStyle(Palette.evergreen.onColor)
                    .contentTransition(.numericText())
            }
            Spacer()
            Image(systemName: "gift.fill").font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.gold.base)
                .frame(width: 64, height: 64)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .padding(Spacing.lg)
        .background(ClayBackground(style: .accent(.evergreen), radius: Radius.lg, elevation: 1.1))
        .padding(.horizontal, Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Available points: \(gameState.pointsBalance)")
    }

    // MARK: - Tier section

    private func rewardSection(tier: RewardTier, rewards: [Reward]) -> some View {
        let locked = isTierLocked(tier)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: 10) {
                ClayIconTile(systemImage: tier.icon, kind: tier.clayKind, size: 38, radius: Radius.chip)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tier.rawValue).font(VType.display(18, .semibold)).foregroundStyle(Palette.ink)
                    Text("\(tier.minPoints)+ pts").font(VType.num(12, .medium)).foregroundStyle(Palette.inkSoft)
                }
                if locked {
                    Spacer()
                    Button { Haptics.tap(); showPaywall = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                            Text("Verdure+").font(VType.body(11, .bold))
                        }
                        .foregroundStyle(Palette.gold.onColor)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(ClayBackground(style: .accent(.gold), radius: Radius.chip, elevation: 0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tier.rawValue) tier requires Verdure Plus")
                    .accessibilityHint("Opens the Verdure Plus subscription page.")
                }
            }
            .padding(.horizontal, Spacing.md)

            VStack(spacing: 12) {
                ForEach(rewards) { reward in rewardCard(reward, tier: tier, locked: locked) }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private func rewardCard(_ reward: Reward, tier: RewardTier, locked: Bool) -> some View {
        let isRedeemed = gameState.isRedeemed(reward.id)
        let canAfford = gameState.canAfford(reward)
        return HStack(spacing: Spacing.md) {
            ClayIconTile(systemImage: reward.icon, kind: tier.clayKind, size: 50, radius: Radius.chip)
            VStack(alignment: .leading, spacing: 3) {
                Text(reward.name).font(VType.display(15, .semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(reward.brand).font(VType.body(12)).foregroundStyle(Palette.inkSoft).lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            if isRedeemed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .bold))
                    Text("Redeemed").font(VType.body(11, .bold))
                }
                .foregroundStyle(Palette.teal.base)
            } else if locked {
                Button { Haptics.tap(); showPaywall = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold))
                        Text("\(reward.pointCost) pts").font(VType.num(13, .bold))
                    }
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(ClayBackground(style: .inset, radius: Radius.chip))
                }
                .buttonStyle(.plain)
            } else {
                Button { Haptics.tap(); confirmingReward = reward } label: {
                    Text("\(reward.pointCost) pts")
                        .font(VType.num(13, .bold))
                        .foregroundStyle(canAfford ? Palette.spruce.onColor : Palette.inkFaint)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(ClayBackground(style: canAfford ? .accent(.spruce) : .inset,
                                                   radius: Radius.chip, elevation: 0.4))
                }
                .disabled(!canAfford || isRedeeming).buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .claySurface(.surface, radius: Radius.md, elevation: isRedeemed ? 0.5 : 0.85)
        .opacity(isRedeemed ? 0.7 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rewardAccessibilityLabel(reward, isRedeemed: isRedeemed, locked: locked, canAfford: canAfford))
        .accessibilityHint(isRedeemed ? "" : (locked ? "Requires Verdure Plus. Double tap to view subscription options."
                                                     : (canAfford ? "Double tap to redeem for \(reward.pointCost) points." : "")))
    }

    private func rewardAccessibilityLabel(_ reward: Reward, isRedeemed: Bool, locked: Bool, canAfford: Bool) -> String {
        var parts = ["\(reward.name) gift card", "\(reward.pointCost) points", "\(reward.tier.rawValue) tier"]
        if isRedeemed { parts.append("already redeemed") }
        else if locked { parts.append("locked, requires Verdure Plus") }
        else if !canAfford { parts.append("not enough points yet") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    RewardsStoreView()
        .environment(GameStateManager())
        .environment(StoreService())
}
