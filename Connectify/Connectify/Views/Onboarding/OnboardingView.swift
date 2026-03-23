import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var selectedInterests: Set<PlaceCategory> = []
    @State private var userName = ""
    @State private var animateIn = false

    private let pages = [
        OnboardingPage(
            icon: "globe.americas.fill",
            title: "Rediscover Your\nNeighborhood",
            subtitle: "Connectify turns local outdoor spaces into adventures waiting to happen.",
            accent: Color.connectifyGreen
        ),
        OnboardingPage(
            icon: "star.fill",
            title: "Earn Rewards\nFor Exploring",
            subtitle: "Complete challenges, collect XP, and unlock badges as you discover new places.",
            accent: Color.accentAmber
        ),
        OnboardingPage(
            icon: "person.3.fill",
            title: "Build Real\nConnections",
            subtitle: "Join events, share discoveries, and grow your local community — face to face.",
            accent: Color.accentSky
        ),
    ]

    var body: some View {
        ZStack {
            Color.pageSurface
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pages.count {
                        Button("Skip") {
                            withAnimation(.spring(response: 0.5)) {
                                currentPage = pages.count
                            }
                        }
                        .font(CFont.caption(15))
                        .foregroundStyle(.secondaryText)
                        .padding(.trailing, Spacing.lg)
                        .padding(.top, Spacing.md)
                    }
                }

                Spacer()

                // Content
                Group {
                    if currentPage < pages.count {
                        welcomePage(pages[currentPage])
                    } else if currentPage == pages.count {
                        interestsPage
                    } else {
                        namePage
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Bottom controls
                VStack(spacing: Spacing.md) {
                    // Page dots
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? Color.connectifyGreen : .subtleBorder)
                                .frame(width: i == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.35), value: currentPage)
                        }
                    }
                    .padding(.bottom, Spacing.sm)

                    ConnectifyButton(
                        title: buttonTitle,
                        icon: currentPage == totalPages - 1 ? "arrow.right" : nil
                    ) {
                        advance()
                    }
                    .padding(.horizontal, Spacing.lg)
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateIn = true
            }
        }
    }

    // MARK: - Welcome Pages

    @ViewBuilder
    private func welcomePage(_ page: OnboardingPage) -> some View {
        VStack(spacing: Spacing.xl) {
            ZStack {
                Circle()
                    .fill(page.accent.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .scaleEffect(animateIn ? 1 : 0.6)

                Circle()
                    .fill(page.accent.opacity(0.06))
                    .frame(width: 220, height: 220)
                    .scaleEffect(animateIn ? 1 : 0.4)

                Image(systemName: page.icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(page.accent)
                    .scaleEffect(animateIn ? 1 : 0.5)
            }
            .animation(.spring(response: 0.7, dampingFraction: 0.6), value: animateIn)

            VStack(spacing: Spacing.md) {
                Text(page.title)
                    .font(CFont.display(32))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primaryText)

                Text(page.subtitle)
                    .font(CFont.body(16))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondaryText)
                    .padding(.horizontal, Spacing.xl)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Interests Page

    private var interestsPage: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("What draws you\noutdoors?")
                    .font(CFont.display(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primaryText)

                Text("Pick a few — we'll personalize your experience.")
                    .font(CFont.body(15))
                    .foregroundStyle(.secondaryText)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PlaceCategory.allCases) { category in
                    InterestTile(
                        label: category.rawValue,
                        icon: category.icon,
                        tint: category.tint,
                        isSelected: selectedInterests.contains(category)
                    ) {
                        if selectedInterests.contains(category) {
                            selectedInterests.remove(category)
                        } else {
                            selectedInterests.insert(category)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    // MARK: - Name Page

    private var namePage: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.connectifyGreen)

            VStack(spacing: Spacing.sm) {
                Text("What should we\ncall you?")
                    .font(CFont.display(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primaryText)

                Text("Just a first name is fine.")
                    .font(CFont.body(15))
                    .foregroundStyle(.secondaryText)
            }

            TextField("Your name", text: $userName)
                .font(CFont.body(18))
                .multilineTextAlignment(.center)
                .padding()
                .background(.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(.subtleBorder, lineWidth: 1)
                }
                .padding(.horizontal, Spacing.xxl)
        }
    }

    // MARK: - Helpers

    private var totalPages: Int { pages.count + 2 }

    private var buttonTitle: String {
        if currentPage < pages.count { return "Continue" }
        if currentPage == pages.count { return selectedInterests.isEmpty ? "Continue" : "Continue (\(selectedInterests.count) selected)" }
        return "Let's Go"
    }

    private func advance() {
        if currentPage >= totalPages - 1 {
            withAnimation(.spring(response: 0.5)) {
                hasCompletedOnboarding = true
            }
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                currentPage += 1
            }
        }
    }
}

// MARK: - Supporting Types

private struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
}

private struct InterestTile: View {
    let label: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isSelected ? tint : .secondaryText)

                Text(label)
                    .font(CFont.caption(14))
                    .foregroundStyle(isSelected ? .primaryText : .secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(isSelected ? tint.opacity(0.10) : .cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(isSelected ? tint.opacity(0.5) : .subtleBorder, lineWidth: isSelected ? 1.5 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
