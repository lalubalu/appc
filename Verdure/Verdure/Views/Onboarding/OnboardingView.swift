import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Environment(AuthService.self) private var authService
    @State private var currentPage = 0
    @State private var selectedInterests: Set<PlaceCategory> = []
    @AppStorage("interestCategories") private var interestCategoriesRaw = ""
    @State private var userName = ""
    @State private var userEmail = ""
    @State private var userPassword = ""
    @State private var isSignUp = true
    @State private var showPasswordField = false
    @State private var animateIn = false
    @State private var isSubmitting = false

    private let pages = [
        OnboardingPage(
            icon: "safari.fill",
            kicker: "Beta · 2026",
            title: "Step Outside.\nConnect Within.",
            subtitle: "Verdure turns your neighborhood into an adventure — discover hidden spots, earn rewards, and connect with your community.",
            kind: .teal
        ),
        OnboardingPage(
            icon: "leaf.fill",
            kicker: "Play the outdoors",
            title: "Earn Rewards\nFor Exploring",
            subtitle: "Complete challenges, collect places, and grow your points into real-world gift cards.",
            kind: .gold
        ),
        OnboardingPage(
            icon: "person.3.fill",
            kicker: "Real, local, human",
            title: "Build Real\nConnections",
            subtitle: "Join nearby events, share discoveries, and grow your local community — face to face.",
            kind: .spruce
        ),
    ]

    var body: some View {
        if currentPage == totalPages - 1 {
            AuthView(onComplete: {
                withAnimation(.spring(response: 0.5)) { hasCompletedOnboarding = true }
            })
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            onboardingFlow
        }
    }

    private var onboardingFlow: some View {
        ZStack {
            VerdureBackground()

            VStack(spacing: 0) {
                // Back / Skip
                HStack {
                    if currentPage > 0 {
                        Button {
                            Haptics.soft()
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { currentPage -= 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                                Text("Back").font(VType.body(15, .medium))
                            }
                            .foregroundStyle(Palette.inkSoft)
                        }
                        .padding(.leading, Spacing.lg).padding(.top, Spacing.md)
                    }
                    Spacer()
                    if currentPage < pages.count {
                        Button("Skip") {
                            withAnimation(.spring(response: 0.5)) { currentPage = pages.count }
                        }
                        .font(VType.body(15, .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.trailing, Spacing.lg).padding(.top, Spacing.md)
                    }
                }

                Spacer()

                Group {
                    if currentPage < pages.count {
                        welcomePage(pages[currentPage], index: currentPage)
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

                VStack(spacing: Spacing.md) {
                    HStack(spacing: 7) {
                        ForEach(0..<totalPages, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? Palette.spruce.base : Palette.surfaceShadow)
                                .frame(width: i == currentPage ? 26 : 8, height: 8)
                                .animation(.spring(response: 0.4), value: currentPage)
                        }
                    }
                    .padding(.bottom, Spacing.sm)

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(VType.body(13, .medium))
                            .foregroundStyle(Palette.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.lg)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ClayButton(buttonTitle,
                               systemImage: currentPage == totalPages - 1 ? "arrow.right" : nil,
                               kind: .spruce, fullWidth: true) { advance() }
                        .disabled(isSubmitting)
                        .opacity(isSubmitting ? 0.6 : 1)
                        .padding(.horizontal, Spacing.lg)
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { animateIn = true }
        }
    }

    // MARK: - Welcome pages

    @ViewBuilder
    private func welcomePage(_ page: OnboardingPage, index: Int) -> some View {
        VStack(spacing: Spacing.xl) {
            ZStack {
                AmbientGlow(color: page.kind.accent.base.opacity(0.35), size: 320, opacity: 0.7)
                if index == 0 {
                    MedallionHero(size: 248)
                        .scaleEffect(animateIn ? 1 : 0.7)
                        .opacity(animateIn ? 1 : 0)
                } else {
                    ClayIconTile(systemImage: page.icon, kind: page.kind, size: 132, radius: Radius.lg)
                        .scaleEffect(animateIn ? 1 : 0.6)
                        .idleFloat(distance: 7, duration: 3.4)
                }
            }
            .frame(height: 270)
            .animation(.spring(response: 0.8, dampingFraction: 0.6), value: animateIn)

            VStack(spacing: Spacing.md) {
                KickerLabel(text: page.kicker, color: page.kind.accent.base, dot: Palette.gold.base)
                Text(page.title)
                    .font(VType.display(38, .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(2)
                Text(page.subtitle)
                    .font(VType.body(16))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, Spacing.xl)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Interests

    private var interestsPage: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("What draws you\noutdoors?")
                    .font(VType.display(30, .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                Text("Pick a few — we'll personalize your map.")
                    .font(VType.body(15))
                    .foregroundStyle(Palette.inkSoft)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PlaceCategory.allCases) { category in
                    InterestTile(
                        category: category,
                        isSelected: selectedInterests.contains(category)
                    ) {
                        if selectedInterests.contains(category) { selectedInterests.remove(category) }
                        else { selectedInterests.insert(category) }
                        interestCategoriesRaw = selectedInterests.map(\.rawValue).joined(separator: ",")
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    // MARK: - Auth

    private var authPage: some View {
        VStack(spacing: Spacing.lg) {
            ClayIconTile(systemImage: isSignUp ? "hand.wave.fill" : "person.fill",
                         kind: .spruce, size: 84, radius: Radius.md)
                .idleFloat(distance: 5, duration: 3)

            VStack(spacing: Spacing.sm) {
                Text(isSignUp ? "Create your\naccount" : "Welcome\nback")
                    .font(VType.display(30, .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                Text(isSignUp ? "Just a few details to get started." : "Sign in to pick up where you left off.")
                    .font(VType.body(15))
                    .foregroundStyle(Palette.inkSoft)
            }

            VStack(spacing: 12) {
                if isSignUp {
                    ClayField(placeholder: "Your name", text: $userName, contentType: .name)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ClayField(placeholder: "Email address", text: $userEmail,
                          contentType: .emailAddress, keyboard: .emailAddress, autocap: false)
                    .onChange(of: userEmail) { _, newValue in
                        if !newValue.isEmpty && !showPasswordField {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showPasswordField = true }
                        }
                    }
                if showPasswordField {
                    ClayField(placeholder: "Password (6+ characters)", text: $userPassword,
                              secure: true, contentType: isSignUp ? .newPassword : .password)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, Spacing.xl)

            Button {
                withAnimation(.spring(response: 0.4)) { isSignUp.toggle(); authService.clearError() }
            } label: {
                Text(isSignUp ? "Already have an account? **Sign in**" : "New here? **Create account**")
                    .font(VType.body(14))
                    .foregroundStyle(Palette.inkSoft)
            }
            .buttonStyle(.plain)

            if isSubmitting {
                ProgressView().tint(Palette.spruce.base).transition(.opacity)
            }
        }
    }

    // MARK: - Helpers

    private var totalPages: Int { pages.count + 2 }

    private var buttonTitle: String {
        if currentPage < pages.count { return "Continue" }
        if currentPage == pages.count {
            return selectedInterests.isEmpty ? "Continue" : "Continue · \(selectedInterests.count) picked"
        }
        if isSubmitting { return "Creating account…" }
        return isSignUp ? "Create Account" : "Sign In"
    }

    private func advance() {
        authService.clearError()
        if currentPage >= totalPages - 1 { submitAuth() }
        else { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { currentPage += 1 } }
    }

    private func submitAuth() {
        isSubmitting = true
        Task {
            do {
                if isSignUp {
                    try await authService.signUp(
                        email: userEmail.trimmingCharacters(in: .whitespaces),
                        password: userPassword,
                        displayName: userName.trimmingCharacters(in: .whitespaces))
                } else {
                    try await authService.signIn(
                        email: userEmail.trimmingCharacters(in: .whitespaces),
                        password: userPassword)
                }
                await MainActor.run {
                    isSubmitting = false
                    Haptics.success()
                    withAnimation(.spring(response: 0.5)) { hasCompletedOnboarding = true }
                }
            } catch {
                await MainActor.run { isSubmitting = false }
            }
        }
    }
}

// MARK: - Supporting types

private struct OnboardingPage {
    let icon: String
    let kicker: String
    let title: String
    let subtitle: String
    let kind: ClayStyle.ClayAccentKind
}

/// Clay inset text field.
struct ClayField: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var autocap: Bool = true

    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) }
            else { TextField(placeholder, text: $text) }
        }
        .font(VType.body(17))
        .foregroundStyle(Palette.ink)
        .padding(.vertical, 16).padding(.horizontal, 18)
        .background(ClayBackground(style: .inset, radius: Radius.sm))
        .textContentType(contentType)
        .keyboardType(keyboard)
        .textInputAutocapitalization(autocap ? .sentences : .never)
        .autocorrectionDisabled(!autocap)
    }
}

private struct InterestTile: View {
    let category: PlaceCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ClayIconTile(systemImage: category.icon, kind: category.clayKind,
                             size: 50, radius: Radius.chip)
                Text(category.rawValue)
                    .font(VType.body(14, .semibold))
                    .foregroundStyle(isSelected ? category.accent.onColor : Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .buttonStyle(ClayPressButtonStyle(
            style: isSelected ? .accent(category.clayKind) : .surface,
            radius: Radius.md, elevation: 0.7))
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environment(AuthService())
}
