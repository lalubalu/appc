import SwiftUI

struct ProfileView: View {
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @Environment(GameStateManager.self) private var gameState
    @Environment(AuthService.self) private var authService
    @State private var showRewardsStore = false
    @State private var showSignOutConfirm = false

    private var displayName: String {
        authService.currentUser?.displayName ?? "Explorer"
    }

    private var initials: String {
        authService.currentUser?.initials ?? "ME"
    }

    private var joinDate: String {
        authService.currentUser?.joinDateFormatted ?? "March 2026"
    }

    private var totalXP: Int {
        gameState.lifetimePoints * 2
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    profileHeader
                    pointsCard
                    statsRow
                    streakCard
                    badgesSection
                    challengesSection
                    settingsSection
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
            .background(.pageSurface)
            .navigationTitle("Profile")
            .sheet(isPresented: $showRewardsStore) {
                RewardsStoreView()
                    .environment(gameState)
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: Spacing.md) {
            // Avatar on green background
            ZStack {
                Circle()
                    .fill(Color.connectifyGreen.opacity(0.12))
                    .frame(width: 100, height: 100)
                AvatarCircle(initials: initials, size: 80)
            }

            VStack(spacing: Spacing.xs) {
                Text(displayName)
                    .font(CFont.title(22))
                    .foregroundStyle(.primaryText)

                if let email = authService.currentUser?.email {
                    Text(email)
                        .font(CFont.caption(12))
                        .foregroundStyle(.tertiaryText)
                }

                Text("Member since \(joinDate)")
                    .font(CFont.caption(13))
                    .foregroundStyle(Color.connectifyGreen)
            }

            // XP bar
            VStack(spacing: 6) {
                HStack {
                    Text("Level \(totalXP / 500 + 1)")
                        .font(CFont.label(12))
                        .foregroundStyle(Color.connectifyGreen)

                    Spacer()

                    Text("\(totalXP) / \((totalXP / 500 + 1) * 500) XP")
                        .font(CFont.label(12))
                        .foregroundStyle(.secondaryText)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.connectifyGreen.opacity(0.12))
                            .frame(height: 8)

                        Capsule()
                            .fill(Color.connectifyGreen)
                            .frame(width: geo.size.width * (Double(totalXP % 500) / 500.0), height: 8)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal, Spacing.xl)
        }
        .padding(.top, Spacing.md)
    }

    // MARK: - Points Card

    private var pointsCard: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("POINTS")
                    .font(CFont.label(10))
                    .tracking(0.8)
                    .foregroundStyle(Color.connectifyGreen)

                Text("\(gameState.pointsBalance)")
                    .font(CFont.mono(32))
                    .foregroundStyle(.primaryText)
                    .contentTransition(.numericText())

                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.connectifyGreen)
                    Text("\(gameState.totalEventsAttended) events · \(gameState.totalCollected) places")
                        .font(CFont.caption(12))
                        .foregroundStyle(.secondaryText)
                }
            }

            Spacer()

            Button {
                showRewardsStore = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 22))
                    Text("Rewards")
                        .font(CFont.label(11))
                }
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Color.connectifyGreen)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(
            HStack(spacing: 0) {
                Color.connectifyGreen
                    .frame(width: 3)
                Color.cardSurface
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: Spacing.sm) {
            StatCard(value: "\(gameState.totalEventsAttended)", label: "Events", icon: "calendar.badge.checkmark")
            StatCard(value: "\(gameState.totalCollected)", label: "Places", icon: "trophy.fill")
            StatCard(value: "7", label: "Day Streak", icon: "flame.fill")
        }
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.connectifyGreen)
                    Text("7-day streak!")
                        .font(CFont.headline(16))
                        .foregroundStyle(.primaryText)
                }

                Text("Visit a place today to keep it going.")
                    .font(CFont.caption(13))
                    .foregroundStyle(.secondaryText)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { _ in
                    Circle()
                        .fill(Color.connectifyGreen)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .padding(Spacing.md)
        .background(.greenCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Badges

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Badges", action: "See All")

            let badges = SampleData.currentUser.badges
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(badges) { badge in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(badge.earned ? Color.connectifyGreen.opacity(0.15) : .cardSurface)
                                .frame(width: 56, height: 56)

                            Image(systemName: badge.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(badge.earned ? Color.connectifyGreen : .tertiaryText)
                        }

                        Text(badge.name)
                            .font(CFont.caption(11))
                            .foregroundStyle(badge.earned ? .primaryText : .tertiaryText)
                    }
                    .opacity(badge.earned ? 1 : 0.4)
                }
            }
        }
    }

    // MARK: - Challenges

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Active Challenges", action: "View All")

            ForEach(SampleData.challenges.prefix(2)) { challenge in
                HStack(spacing: Spacing.md) {
                    ProgressRing(progress: challenge.progress, size: 42, lineWidth: 3.5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.title)
                            .font(CFont.headline(15))
                            .foregroundStyle(.primaryText)

                        Text(challenge.description)
                            .font(CFont.caption(12))
                            .foregroundStyle(.secondaryText)
                    }

                    Spacer()

                    XPBadge(xp: challenge.xpReward)
                }
                .greenAccentCard()
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Settings")

            VStack(spacing: 0) {
                settingsRow(icon: "moon.fill", label: "Dark Mode") {
                    Toggle("", isOn: $prefersDarkMode)
                        .tint(Color.connectifyGreen)
                        .labelsHidden()
                }

                Divider().padding(.leading, 52)

                settingsRow(icon: "bell.fill", label: "Notifications") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiaryText)
                }

                Divider().padding(.leading, 52)

                settingsRow(icon: "lock.fill", label: "Privacy") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiaryText)
                }

                Divider().padding(.leading, 52)

                settingsRow(icon: "info.circle.fill", label: "About Connectify") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiaryText)
                }
            }
            .background(.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            // Sign out
            Button {
                showSignOutConfirm = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                    Text("Sign Out")
                        .font(CFont.headline(15))
                }
                .foregroundStyle(Color.connectifyDestructive)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Sign out of Connectify?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    authService.signOut()
                    gameState.disconnectCloud()
                    withAnimation {
                        hasCompletedOnboarding = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func settingsRow<Trailing: View>(icon: String, label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.connectifyGreen)
                .frame(width: 28)

            Text(label)
                .font(CFont.body(15))
                .foregroundStyle(.primaryText)

            Spacer()

            trailing()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 13)
    }
}

#Preview {
    ProfileView()
        .environment(GameStateManager())
        .environment(AuthService())
}
