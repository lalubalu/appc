import SwiftUI

struct ProfileView: View {
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    private let user = SampleData.currentUser

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    // Profile header
                    profileHeader

                    // Stats row
                    statsRow

                    // Current streak
                    streakCard

                    // Badges
                    badgesSection

                    // Active challenges
                    challengesSection

                    // Settings
                    settingsSection
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
            .background(.pageSurface)
            .navigationTitle("Profile")
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: Spacing.md) {
            AvatarCircle(initials: user.initials, size: 80)

            VStack(spacing: Spacing.xs) {
                Text(user.name)
                    .font(CFont.title(22))
                    .foregroundStyle(.primaryText)

                Text("Member since \(user.joinDate)")
                    .font(CFont.caption(13))
                    .foregroundStyle(.secondaryText)
            }

            // XP bar
            VStack(spacing: 6) {
                HStack {
                    Text("Level \(user.totalXP / 500 + 1)")
                        .font(CFont.label(11))
                        .foregroundStyle(Color.connectifyGreen)

                    Spacer()

                    Text("\(user.totalXP) / \((user.totalXP / 500 + 1) * 500) XP")
                        .font(CFont.label(11))
                        .foregroundStyle(.secondaryText)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.subtleBorder)
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.connectifyGreen)
                            .frame(width: geo.size.width * (Double(user.totalXP % 500) / 500.0), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, Spacing.xl)
        }
        .padding(.top, Spacing.md)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: Spacing.sm) {
            StatCard(value: "\(user.placesVisited)", label: "Visited", icon: "mappin.circle.fill")
            StatCard(value: "\(user.totalXP)", label: "Total XP", icon: "bolt.fill")
            StatCard(value: "\(user.currentStreak)", label: "Day Streak", icon: "flame.fill")
        }
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.accentCoral)
                    Text("\(user.currentStreak)-day streak!")
                        .font(CFont.headline(16))
                        .foregroundStyle(.primaryText)
                }

                Text("Visit a place today to keep it going.")
                    .font(CFont.caption(13))
                    .foregroundStyle(.secondaryText)
            }

            Spacer()

            // Week dots
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { day in
                    Circle()
                        .fill(day < user.currentStreak ? Color.connectifyGreen : .subtleBorder)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .padding(Spacing.md)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(.subtleBorder, lineWidth: 0.5)
        }
    }

    // MARK: - Badges

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Badges", action: "See All")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(user.badges) { badge in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(badge.earned ? .greenSurface : .cardSurface)
                                .frame(width: 56, height: 56)

                            Image(systemName: badge.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(badge.earned ? Color.connectifyGreen : .tertiaryText)
                        }

                        Text(badge.name)
                            .font(CFont.caption(11))
                            .foregroundStyle(badge.earned ? .primaryText : .tertiaryText)
                    }
                    .opacity(badge.earned ? 1 : 0.5)
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
                .padding(Spacing.md)
                .background(.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(.subtleBorder, lineWidth: 0.5)
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Settings")
                .font(CFont.title(20))
                .foregroundStyle(.primaryText)

            VStack(spacing: 0) {
                // Dark mode toggle
                settingsRow(icon: "moon.fill", label: "Dark Mode") {
                    Toggle("", isOn: $prefersDarkMode)
                        .tint(Color.connectifyGreen)
                        .labelsHidden()
                }

                Divider().padding(.leading, 52)

                // Notifications
                settingsRow(icon: "bell.fill", label: "Notifications") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiaryText)
                }

                Divider().padding(.leading, 52)

                // Privacy
                settingsRow(icon: "lock.fill", label: "Privacy") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiaryText)
                }

                Divider().padding(.leading, 52)

                // About
                settingsRow(icon: "info.circle.fill", label: "About Connectify") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiaryText)
                }
            }
            .background(.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(.subtleBorder, lineWidth: 0.5)
            }

            // Sign out
            Button {
                withAnimation {
                    hasCompletedOnboarding = false
                }
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
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(Color.connectifyDestructive.opacity(0.2), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
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
}
