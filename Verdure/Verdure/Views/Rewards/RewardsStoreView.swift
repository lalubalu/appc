import SwiftUI

struct RewardsStoreView: View {
    @Environment(GameStateManager.self) private var gameState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReward: Reward? = nil
    @State private var redeemedReward: Reward? = nil

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
                        if gameState.redeemReward(reward) {
                            Haptics.success(); redeemedReward = reward
                        }
                        confirmingReward = nil
                    }
                }
            } message: {
                if let reward = confirmingReward { Text("Spend \(reward.pointCost) points on \(reward.name)?") }
            }
            .sheet(item: $redeemedReward) { reward in
                RewardConfirmationView(reward: reward)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
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
    }

    // MARK: - Tier section

    private func rewardSection(tier: RewardTier, rewards: [Reward]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: 10) {
                ClayIconTile(systemImage: tier.icon, kind: tier.clayKind, size: 38, radius: Radius.chip)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tier.rawValue).font(VType.display(18, .semibold)).foregroundStyle(Palette.ink)
                    Text("\(tier.minPoints)+ pts").font(VType.num(12, .medium)).foregroundStyle(Palette.inkSoft)
                }
            }
            .padding(.horizontal, Spacing.md)

            VStack(spacing: 12) {
                ForEach(rewards) { reward in rewardCard(reward, tier: tier) }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private func rewardCard(_ reward: Reward, tier: RewardTier) -> some View {
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
            } else {
                Button { Haptics.tap(); confirmingReward = reward } label: {
                    Text("\(reward.pointCost) pts")
                        .font(VType.num(13, .bold))
                        .foregroundStyle(canAfford ? Palette.spruce.onColor : Palette.inkFaint)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(ClayBackground(style: canAfford ? .accent(.spruce) : .inset,
                                                   radius: Radius.chip, elevation: 0.4))
                }
                .disabled(!canAfford).buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .claySurface(.surface, radius: Radius.md, elevation: isRedeemed ? 0.5 : 0.85)
        .opacity(isRedeemed ? 0.7 : 1)
    }
}

#Preview {
    RewardsStoreView()
        .environment(GameStateManager())
}
