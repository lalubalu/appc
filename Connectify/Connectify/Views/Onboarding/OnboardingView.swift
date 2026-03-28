import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Environment(AuthService.self) private var authService
    @State private var currentPage = 0
    @State private var selectedInterests: Set<PlaceCategory> = []
    @State private var userName = ""
    @State private var userEmail = ""
    @State private var userPassword = ""
    @State private var isSignUp = true
    @State private var showPasswordField = false
    @State private var animateIn = false
    @State private var isSubmitting = false

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
                        authPage
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

                    // Error message
                    if let error = authService.errorMessage {
                        Text(error)
                            .font(CFont.caption(13))
                            .foregroundStyle(Color.connectifyDestructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.lg)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ConnectifyButton(
                        title: buttonTitle,
                        icon: currentPage == totalPages - 1 ? "arrow.right" : nil
                    ) {
                        advance()
                    }
                    .disabled(isSubmitting)
                    .opacity(isSubmitting ? 0.6 : 1)
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

    // MARK: - Auth Page (Name + Email + Password)

    private var authPage: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: isSignUp ? "hand.wave.fill" : "person.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.connectifyGreen)

            VStack(spacing: Spacing.sm) {
                Text(isSignUp ? "Create your\naccount" : "Welcome\nback")
                    .font(CFont.display(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primaryText)

                Text(isSignUp ? "Just a few details to get started." : "Sign in to pick up where you left off.")
                    .font(CFont.body(15))
                    .foregroundStyle(.secondaryText)
            }

            VStack(spacing: 12) {
                // Name field (sign-up only)
                if isSignUp {
                    TextField("Your name", text: $userName)
                        .font(CFont.body(17))
                        .padding()
                        .background(.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(.subtleBorder, lineWidth: 1)
                        }
                        .textContentType(.name)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Email field
                TextField("Email address", text: $userEmail)
                    .font(CFont.body(17))
                    .padding()
                    .background(.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(.subtleBorder, lineWidth: 1)
                    }
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: userEmail) { _, newValue in
                        if !newValue.isEmpty && !showPasswordField {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                showPasswordField = true
                            }
                        }
                    }

                // Password field — slides in smoothly after email is typed
                if showPasswordField {
                    SecureField("Password (6+ characters)", text: $userPassword)
                        .font(CFont.body(17))
                        .padding()
                        .background(.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(.subtleBorder, lineWidth: 1)
                        }
                        .textContentType(isSignUp ? .newPassword : .password)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, Spacing.xxl)

            // Toggle sign-up / sign-in
            Button {
                withAnimation(.spring(response: 0.4)) {
                    isSignUp.toggle()
                    authService.clearError()
                }
            } label: {
                Text(isSignUp ? "Already have an account? **Sign in**" : "New here? **Create account**")
                    .font(CFont.caption(14))
                    .foregroundStyle(.secondaryText)
            }
            .buttonStyle(.plain)

            if isSubmitting {
                ProgressView()
                    .tint(Color.connectifyGreen)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Helpers

    private var totalPages: Int { pages.count + 2 }

    private var buttonTitle: String {
        if currentPage < pages.count { return "Continue" }
        if currentPage == pages.count { return selectedInterests.isEmpty ? "Continue" : "Continue (\(selectedInterests.count) selected)" }
        if isSubmitting { return "Creating account..." }
        return isSignUp ? "Create Account" : "Sign In"
    }

    private func advance() {
        authService.clearError()

        if currentPage >= totalPages - 1 {
            // Auth page — submit
            submitAuth()
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                currentPage += 1
            }
        }
    }

    private func submitAuth() {
        isSubmitting = true

        Task {
            do {
                if isSignUp {
                    try await authService.signUp(
                        email: userEmail.trimmingCharacters(in: .whitespaces),
                        password: userPassword,
                        displayName: userName.trimmingCharacters(in: .whitespaces)
                    )
                } else {
                    try await authService.signIn(
                        email: userEmail.trimmingCharacters(in: .whitespaces),
                        password: userPassword
                    )
                }

                await MainActor.run {
                    isSubmitting = false
                    withAnimation(.spring(response: 0.5)) {
                        hasCompletedOnboarding = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                }
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
        .environment(AuthService())
}
