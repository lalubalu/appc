import SwiftUI

struct RewardConfirmationView: View {
    let reward: Reward
    @Environment(\.dismiss) private var dismiss
    @State private var showCheck = false
    @State private var showContent = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color.connectifyGreen.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .scaleEffect(showCheck ? 1 : 0.3)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.connectifyGreen)
                    .scaleEffect(showCheck ? 1 : 0)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showCheck)

            VStack(spacing: Spacing.sm) {
                Text("Reward Redeemed!")
                    .font(CFont.title(22))
                    .foregroundStyle(.primaryText)

                Text(reward.name)
                    .font(CFont.headline(18))
                    .foregroundStyle(reward.tier.color)

                Text("Your gift card code will appear here once connected to a rewards backend.")
                    .font(CFont.body(14))
                    .foregroundStyle(.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                // Placeholder code
                Text("XXXX-XXXX-XXXX")
                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiaryText)
                    .padding(.vertical, Spacing.md)
                    .padding(.horizontal, Spacing.lg)
                    .background(.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(.subtleBorder, style: StrokeStyle(lineWidth: 1, dash: [6]))
                    }
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

            Spacer()

            ConnectifyButton(title: "Done", icon: "checkmark") {
                dismiss()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
        .background(.pageSurface)
        .onAppear {
            showCheck = true
            showContent = true
        }
    }
}

// Make Reward usable with .sheet(item:)
extension Reward: Equatable {
    static func == (lhs: Reward, rhs: Reward) -> Bool { lhs.id == rhs.id }
}

extension Reward: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    RewardConfirmationView(reward: SampleData.rewards[0])
}
