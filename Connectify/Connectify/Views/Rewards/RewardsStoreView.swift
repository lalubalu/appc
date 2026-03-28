import SwiftUI

struct RewardsStoreView: View {
    @Environment(GameStateManager.self) private var gameState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReward: Reward? = nil
    @State private var redeemedReward: Reward? = nil

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    balanceHeader

                    ForEach(RewardTier.allCases) { tier in
                        let tierRewards = SampleData.rewards.filter { $0.tier == tier }
                        if !tierRewards.isEmpty {
                            rewardSection(tier: tier, rewards: tierRewards)
                        }
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(.pageSurface)
            .navigationTitle("Rewards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.connectifyGreen)
                }
            }
            .alert("Redeem Reward?", isPresented: Binding(
                get: { confirmingReward != nil },
                set: { if !$0 { confirmingReward = nil } }
            )) {
                Button("Cancel", role: .cancel) { confirmingReward = nil }
                Button("Redeem") {
                    if let reward = confirmingReward {
                        gameState.redeemReward(reward)
                        redeemedReward = reward
                        confirmingReward = nil
                    }
                }
            } message: {
                if let reward = confirmingReward {
                    Text("Spend \(reward.pointCost) points on \(reward.name)?")
                }
            }
            .sheet(item: $redeemedReward) { reward in
                RewardConfirmationView(reward: reward)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Balance Header

    private var balanceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Available Points")
                    .font(CFont.caption(13))
                    .foregroundStyle(Color.connectifyGreenBright.opacity(0.7))
                Text("\(gameState.pointsBalance)")
                    .font(CFont.mono(32))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            Spacer()

            Image(systemName: "gift.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(Spacing.lg)
        .background(Color.connectifyGreenDeep)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Reward Section

    private func rewardSection(tier: RewardTier, rewards: [Reward]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: tier.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.connectifyGreen)
                Text(tier.rawValue)
                    .font(CFont.headline(16))
                    .foregroundStyle(.primaryText)
                Text("\(tier.minPoints)+ pts")
                    .font(CFont.caption(13))
                    .foregroundStyle(.secondaryText)
            }
            .padding(.horizontal, Spacing.md)

            ForEach(rewards) { reward in
                rewardCard(reward)
            }
        }
    }

    private func rewardCard(_ reward: Reward) -> some View {
        let isRedeemed = gameState.isRedeemed(reward.id)
        let canAfford = gameState.canAfford(reward)

        return HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.connectifyGreen.opacity(0.10))
                    .frame(width: 48, height: 48)
                Image(systemName: reward.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.connectifyGreen)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(reward.name)
                    .font(CFont.headline(15))
                    .foregroundStyle(.primaryText)
                Text(reward.brand)
                    .font(CFont.caption(12))
                    .foregroundStyle(.secondaryText)
            }

            Spacer()

            if isRedeemed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Redeemed")
                        .font(CFont.label(11))
                }
                .foregroundStyle(Color.connectifyGreen)
            } else {
                Button {
                    confirmingReward = reward
                } label: {
                    Text("\(reward.pointCost) pts")
                        .font(CFont.headline(13))
                        .foregroundStyle(canAfford ? .white : .tertiaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(canAfford ? Color.connectifyGreen : .cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                }
                .disabled(!canAfford)
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(isRedeemed ? Color.greenCard : Color.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .opacity(isRedeemed ? 0.7 : 1)
        .padding(.horizontal, Spacing.md)
    }
}

#Preview {
    RewardsStoreView()
        .environment(GameStateManager())
}
