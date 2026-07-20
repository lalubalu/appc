import SwiftUI
import PhotosUI

struct ProfileView: View {
    /// Muted brick red for the destructive Sign Out action — reads on both cream + graphite.
    static let signOutRed = Color(red: 0.82, green: 0.28, blue: 0.25)
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @AppStorage("profileImageData") private var profileImageData = Data()
    @State private var photoItem: PhotosPickerItem?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("accountType") private var accountTypeRaw = AccountType.visitor.rawValue
    @Environment(GameStateManager.self) private var gameState
    @Environment(AuthService.self) private var authService
    @Environment(StoreService.self) private var store
    @State private var showRewardsStore = false
    @State private var showPaywall = false
    @State private var showSignOutConfirm = false
    @State private var showOrganizerVerify = false
    @State private var showAllBadges = false
    @State private var showAllChallenges = false
    @State private var showAbout = false
    @State private var showNotifSettings = false
    @State private var selectedBadge: Badge?
    @State private var selectedChallenge: Challenge?
    @State private var heroAppeared = false

    private var displayName: String { authService.currentUser?.displayName ?? "Explorer" }
    private var initials: String { authService.currentUser?.initials ?? "ME" }
    private var joinDate: String { authService.currentUser?.joinDateFormatted ?? "March 2026" }
    private var totalXP: Int { gameState.lifetimePoints * 2 }
    private var level: Int { totalXP / 500 + 1 }
    private var levelProgress: Double { Double(totalXP % 500) / 500.0 }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.xl) {
                    playerCard.dramaticRise(index: 0)
                    statsOrbit.dramaticRise(index: 1)
                    badgesConstellation.dramaticRise(index: 2)
                    challengesRail.dramaticRise(index: 3)
                    settingsSection.dramaticRise(index: 4)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, 110)
            }
            .background(VerdureBackground())
            .sheet(isPresented: $showRewardsStore) {
                RewardsStoreView().environment(gameState)
            }
            .sheet(isPresented: $showAllBadges) {
                AllBadgesView(badges: SampleData.currentUser.badges)
            }
            .sheet(isPresented: $showAllChallenges) {
                AllChallengesView(challenges: SampleData.challenges)
            }
            .sheet(isPresented: $showAbout) { AboutVerdureView() }
            .sheet(isPresented: $showNotifSettings) { NotificationSettingsView() }
            .sheet(item: $selectedBadge) { BadgeDetailSheet(badge: $0) }
            .sheet(item: $selectedChallenge) { ChallengeDetailSheet(challenge: $0) }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data),
                       let jpeg = ui.downscaled().jpegData(compressionQuality: 0.85) {
                        await MainActor.run {
                            Haptics.success()
                            profileImageData = jpeg
                        }
                    }
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.15)) { heroAppeared = true }
            }
        }
    }

    // MARK: - Player card (full-bleed 3D trading card)

    private var playerCard: some View {
        let avatarInitials = initials
        return ZStack {
            // ambient depth behind the medallion
            FloatingBlob(color: Palette.teal.base.opacity(0.45), size: 150, delay: 0).offset(x: -80, y: -60)
            FloatingBlob(color: Palette.gold.base.opacity(0.4), size: 120, delay: 0.7).offset(x: 90, y: 10)

            VStack(spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            UserAvatar(initials: avatarInitials, size: 52, accent: Palette.teal)
                            Image(systemName: "camera.fill").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Palette.spruce.onColor)
                                .padding(5).background(Circle().fill(Palette.spruce.base))
                                .overlay(Circle().strokeBorder(Palette.evergreen.base, lineWidth: 1.5))
                                .offset(x: 3, y: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PLAYER CARD").font(VType.body(12, .bold)).tracking(2.5)
                            .foregroundStyle(Palette.gold.base)
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                        Text(displayName).font(VType.display(26, .bold))
                            .foregroundStyle(Palette.evergreen.onColor).lineLimit(1).minimumScaleFactor(0.7)
                        Text("Member since \(joinDate)")
                            .font(VType.body(12, .medium))
                            .foregroundStyle(Palette.evergreen.onColor.opacity(0.6))
                    }
                    Spacer()
                    rewardsButton
                }

                ZStack {
                    PulseHalo(color: Palette.teal.base.opacity(0.7), size: 130, lineWidth: 2)
                    PulseHalo(color: Palette.gold.base.opacity(0.5), size: 160, lineWidth: 1.5)
                    MedallionHero(size: 150, interactive: true).breathing(scale: 1.05, duration: 3)
                }
                .frame(height: 150)

                // Oversized level number that bleeds to the corner
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: -10) {
                        Text("LEVEL").font(VType.body(11, .bold)).tracking(2.5)
                            .foregroundStyle(Palette.evergreen.onColor.opacity(0.7))
                        CountUp(value: level)
                            .font(VType.num(72, .bold)).monospacedDigit()
                            .foregroundStyle(
                                LinearGradient(colors: [Palette.gold.gloss, Palette.gold.base],
                                               startPoint: .top, endPoint: .bottom))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        CountUp(value: gameState.pointsBalance)
                            .font(VType.num(30, .bold)).monospacedDigit()
                            .foregroundStyle(Palette.evergreen.onColor)
                        Text("points").font(VType.body(11, .medium))
                            .foregroundStyle(Palette.evergreen.onColor.opacity(0.6))
                    }
                }

                VStack(spacing: 6) {
                    HStack {
                        Text("\(totalXP) XP").font(VType.num(11, .bold))
                            .foregroundStyle(Palette.evergreen.onColor.opacity(0.8))
                        Spacer()
                        Text("\(level * 500) XP → level \(level + 1)")
                            .font(VType.num(11, .medium))
                            .foregroundStyle(Palette.evergreen.onColor.opacity(0.55))
                    }
                    ClayProgressBar(value: heroAppeared ? levelProgress : 0,
                                    gradient: [Palette.teal.base, Palette.teal.gloss, Palette.gold.base],
                                    height: 14)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        // Clip the content (floating blobs) to the card shape, THEN draw the clay
        // background behind it so its outer float shadow isn't clipped away.
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .background(ClayBackground(style: .accent(.evergreen), radius: Radius.xl, elevation: 1.3))
        .parallaxTilt(magnitude: 6, shadow: false)
    }

    private var rewardsButton: some View {
        Button { Haptics.tap(); showRewardsStore = true } label: {
            VStack(spacing: 4) {
                Image(systemName: "gift.fill").font(.system(size: 20, weight: .semibold))
                Text("Rewards").font(VType.body(10, .bold))
            }
            .foregroundStyle(Palette.gold.onColor)
            .frame(width: 68, height: 68)
            .background(ClayBackground(style: .accent(.gold), radius: Radius.md, elevation: 0.5))
        }
        .buttonStyle(.plain)
        .breathing(scale: 1.05, duration: 2.4)
    }

    // MARK: - Stats orbit (broken-alignment count-up tiles)

    private var statsOrbit: some View {
        HStack(spacing: 10) {
            statTile(gameState.totalEventsAttended, "Events", "calendar.badge.checkmark", .spruce, dy: 0)
            statTile(gameState.totalCollected, "Places", "leaf.fill", .teal, dy: 14)
            statTile(SampleData.currentUser.currentStreak, "Streak", "flame.fill", .terracotta, dy: 0)
            statTile(gameState.lifetimePoints, "Lifetime", "sparkles", .gold, dy: 14)
        }
    }

    private func statTile(_ value: Int, _ label: String, _ icon: String,
                          _ kind: ClayStyle.ClayAccentKind, dy: CGFloat) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(kind.accent.base)
            CountUp(value: value).font(VType.num(22, .bold)).monospacedDigit().foregroundStyle(Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(VType.body(10, .medium)).foregroundStyle(Palette.inkSoft).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Spacing.md)
        .claySurface(.surface, radius: Radius.md, elevation: 0.8)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(kind.accent.base.opacity(0.38), lineWidth: 1.5))
        .offset(y: dy)
    }

    // MARK: - Badges constellation (scattered)

    private var badgesConstellation: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Badges", action: "See All") { Haptics.tap(); showAllBadges = true }
            let badges = SampleData.currentUser.badges
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 22) {
                ForEach(Array(badges.enumerated()), id: \.element.id) { i, badge in
                    Button { Haptics.soft(); selectedBadge = badge } label: {
                        badgeTile(badge, index: i)
                    }
                    .buttonStyle(.plain)
                    .offset(y: [0, 9, 4][i % 3])
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func badgeTile(_ badge: Badge, index: Int) -> some View {
        VStack(spacing: 9) {
            ZStack {
                if badge.earned {
                    let bk: ClayStyle.ClayAccentKind = [.teal, .gold, .spruce, .terracotta][index % 4]
                    PulseHalo(color: bk.accent.base.opacity(0.6), size: 64, lineWidth: 1.5)
                    ClayIconTile(systemImage: badge.icon, kind: bk, size: 58, radius: Radius.chip)
                        .idleFloat(distance: 3, duration: 2.8 + Double(index % 3) * 0.4)
                } else {
                    Image(systemName: badge.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 58, height: 58)
                        .background(ClayBackground(style: .inset, radius: Radius.chip))
                }
            }
            .frame(height: 64)
            Text(badge.name).font(VType.body(10.5, .semibold))
                .foregroundStyle(badge.earned ? Palette.ink : Palette.inkFaint)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .opacity(badge.earned ? 1 : 0.55)
    }

    // MARK: - Challenges rail

    private var challengesRail: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Active Challenges", action: "View All") { Haptics.tap(); showAllChallenges = true }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(SampleData.challenges.enumerated()), id: \.element.id) { i, c in
                        Button { Haptics.soft(); selectedChallenge = c } label: {
                            challengeCard(c, kind: [.teal, .gold, .spruce, .terracotta][i % 4])
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func challengeCard(_ challenge: Challenge, kind: ClayStyle.ClayAccentKind) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                ClayIconTile(systemImage: challenge.icon, kind: kind, size: 40, radius: Radius.chip)
                Spacer()
                NeonProgressRing(progress: challenge.progress, size: 40, lineWidth: 4, color: kind.accent.base)
            }
            Text(challenge.title).font(VType.display(15, .semibold)).foregroundStyle(Palette.ink)
            Text(challenge.description).font(VType.body(11.5)).foregroundStyle(Palette.inkSoft)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            XPBadge(xp: challenge.xpReward)
        }
        .padding(Spacing.md)
        .frame(width: 184, height: 168, alignment: .topLeading)
        .claySurface(.surface, radius: Radius.md, elevation: 0.85)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(kind.accent.base.opacity(0.4), lineWidth: 1.5))
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Settings")
            VStack(spacing: 0) {
                Button { Haptics.tap(); showPaywall = true } label: {
                    settingsRow(icon: "sparkles", label: "Verdure+", accent: .gold) {
                        if store.isPlus {
                            Text("Active").font(VType.body(12, .bold)).foregroundStyle(Palette.spruce.base)
                        } else {
                            HStack(spacing: 6) {
                                Text("Upgrade").font(VType.body(12, .bold)).foregroundStyle(Palette.gold.base)
                                chevron
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isPlus ? "Verdure Plus, active" : "Verdure Plus, upgrade")
                .accessibilityHint("Opens the Verdure Plus subscription page.")
                rowDivider
                settingsRow(icon: "moon.fill", label: "Dark Mode", accent: .spruce) {
                    Toggle("", isOn: $prefersDarkMode).tint(Palette.spruce.base).labelsHidden()
                }
                rowDivider
                if accountTypeRaw == AccountType.organizer.rawValue {
                    settingsRow(icon: "checkmark.seal.fill", label: "Verified Organizer", accent: .spruce) {
                        Text("Active").font(VType.body(12, .bold)).foregroundStyle(Palette.spruce.base)
                    }
                } else {
                    Button { Haptics.tap(); showOrganizerVerify = true } label: {
                        settingsRow(icon: "megaphone.fill", label: "Become an Organizer", accent: .terracotta) { chevron }
                    }
                    .buttonStyle(.plain)
                }
                rowDivider
                Button { Haptics.tap(); showNotifSettings = true } label: {
                    settingsRow(icon: "bell.fill", label: "Notifications", accent: .gold) { chevron }
                }
                .buttonStyle(.plain)
                rowDivider
                settingsRow(icon: "lock.fill", label: "Privacy", accent: .teal) { chevron }
                rowDivider
                Button { Haptics.tap(); showAbout = true } label: {
                    settingsRow(icon: "info.circle.fill", label: "About Verdure", accent: .terracotta) { chevron }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
            .claySurface(.surface, radius: Radius.md)

            Button { Haptics.tap(); showSignOutConfirm = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 16, weight: .bold))
                    Text("Sign Out").font(VType.body(17, .bold))
                }
                .foregroundStyle(Self.signOutRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(ClayBackground(style: .surface, radius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Self.signOutRed.opacity(0.4), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Sign out of Verdure?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    authService.signOut(); gameState.disconnectCloud()
                    withAnimation { hasCompletedOnboarding = false }
                }
                Button("Reset Demo Data", role: .destructive) { gameState.resetAll() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showOrganizerVerify) { OrganizerVerificationView() }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkFaint)
    }
    private var rowDivider: some View {
        ClayHairline().padding(.leading, 56).padding(.trailing, Spacing.md)
    }

    private func settingsRow<Trailing: View>(icon: String, label: String, accent: ClayStyle.ClayAccentKind,
                                              @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent.accent.onColor)
                .frame(width: 32, height: 32)
                .background(ClayBackground(style: .accent(accent), radius: 10, elevation: 0.3))
            Text(label).font(VType.body(15, .medium)).foregroundStyle(Palette.ink)
            Spacer()
            trailing()
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 11)
    }
}

#Preview {
    ProfileView()
        .environment(GameStateManager())
        .environment(AuthService())
        .environment(StoreService())
}
