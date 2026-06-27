import SwiftUI

struct CommunityView: View {
    @Environment(FirestoreService.self) private var firestore
    @Environment(AuthService.self) private var authService
    @State private var posts: [CommunityPost] = SampleData.communityPosts
    @State private var newPostText = ""
    @State private var showNewPost = false
    @State private var selectedProfile: CommunityProfile?

    /// Load real community posts from Firestore; fall back to sample data when there
    /// are none yet (or the user isn't signed in, since the feed requires auth).
    private func loadPosts() async {
        let remote = await firestore.fetchRecentPosts()
        if !remote.isEmpty { posts = remote + SampleData.communityPosts.prefix(2) }
    }

    private let storyNames: [(String, String)] = [
        ("MC", "Maya"), ("JE", "Jordan"), ("PS", "Priya"), ("AR", "Alex"), ("TK", "Tomo"), ("LW", "Lena")
    ]
    private let trending = ["Botanica Gardens", "Hawk Ridge", "Marina Point", "The Commons",
                            "Riverside Park", "Overlook Bluff", "Cedar Court"]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        header.dramaticRise(index: 0)
                        storyRail.dramaticRise(index: 1)
                        trendingTicker.dramaticRise(index: 2)
                        feed
                    }
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, 110)
                }
                .background(VerdureBackground())
                composeFAB
            }
            .sheet(isPresented: $showNewPost) {
                newPostSheet.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedProfile) { CommunityProfileSheet(profile: $0) }
            .task { await loadPosts() }
            .refreshable { await loadPosts() }
        }
    }

    private func kind(for index: Int) -> ClayStyle.ClayAccentKind {
        [.teal, .gold, .spruce, .terracotta][index % 4]
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            KickerLabel(text: "What's blooming nearby", dot: Palette.gold.base)
            Text("Community").font(VType.display(44, .bold)).foregroundStyle(Palette.ink)
            HStack(spacing: 6) {
                Circle().fill(Palette.teal.base).frame(width: 8, height: 8).breathing(scale: 1.4, duration: 1.4)
                CountUp(value: 247).font(VType.num(14, .bold)).foregroundStyle(Palette.ink)
                Text("explorers active now").font(VType.body(13, .medium)).foregroundStyle(Palette.inkSoft)
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Story rail

    private var storyRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                StoryRing(initials: "ME", name: "Your story", accent: Palette.spruce, isYou: true)
                    .onTapGesture { Haptics.tap(); showNewPost = true }
                ForEach(Array(storyNames.enumerated()), id: \.offset) { i, s in
                    let accent = Palette.accentCycle[i % Palette.accentCycle.count]
                    StoryRing(initials: s.0, name: s.1, accent: accent, isYou: false)
                        .onTapGesture {
                            Haptics.soft()
                            selectedProfile = CommunityProfile(name: s.1, initials: s.0, accent: accent)
                        }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Trending marquee

    private var trendingTicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRENDING").font(VType.body(10, .bold)).tracking(1.6)
                .foregroundStyle(Palette.inkSoft).padding(.horizontal, Spacing.md)
            Marquee(spacing: 12, speed: 36) {
                HStack(spacing: 12) {
                    ForEach(Array(trending.enumerated()), id: \.offset) { i, t in
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.accentCycle[i % Palette.accentCycle.count].base)
                            Text(t).font(VType.body(13, .semibold)).foregroundStyle(Palette.ink)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(ClayBackground(style: .surface, radius: Radius.chip, elevation: 0.4))
                    }
                }
            }
            .frame(height: 40)
        }
    }

    // MARK: - Feed (staggered / broken grid)

    private var feed: some View {
        LazyVStack(spacing: 18) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { i, post in
                HStack(spacing: 0) {
                    if i % 2 == 1 { Spacer(minLength: 26) }
                    PostCard(post: post, accent: kind(for: i)) {
                        guard post.authorName != "You" else { return }
                        Haptics.soft()
                        selectedProfile = CommunityProfile(name: post.authorName,
                                                           initials: post.authorInitials,
                                                           accent: kind(for: i).accent)
                    }
                        .rotationEffect(.degrees(i % 2 == 0 ? -1.2 : 1.2))
                    if i % 2 == 0 { Spacer(minLength: 26) }
                }
                .padding(.horizontal, Spacing.md)
                .scrollTransition(.animated(.spring(response: 0.5, dampingFraction: 0.8))) { c, phase in
                    c.opacity(phase.isIdentity ? 1 : 0)
                     .offset(y: phase.isIdentity ? 0 : 34)
                     .scaleEffect(phase.isIdentity ? 1 : 0.9)
                }
            }
        }
    }

    // MARK: - Compose FAB

    private var composeFAB: some View {
        Button { Haptics.tap(); showNewPost = true } label: {
            Image(systemName: "square.and.pencil").font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.spruce.onColor)
                .frame(width: 62, height: 62)
                .background(ClayBackground(style: .accent(.spruce), radius: Radius.md, elevation: 0.9))
        }
        .buttonStyle(.plain)
        .breathing(scale: 1.06, duration: 2.2)
        .padding(.trailing, Spacing.lg)
        .padding(.bottom, 100)
    }

    // MARK: - New post sheet

    private var newPostSheet: some View {
        NavigationStack {
            ZStack {
                VerdureBackground()
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        AvatarCircle(initials: "ME", size: 42, accent: Palette.teal)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("You").font(VType.display(15, .semibold)).foregroundStyle(Palette.ink)
                            Text("Posting to the neighborhood")
                                .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                    }
                    TextField("What did you discover today?", text: $newPostText, axis: .vertical)
                        .font(VType.body(16)).foregroundStyle(Palette.ink)
                        .lineLimit(5...10).padding(14)
                        .background(ClayBackground(style: .inset, radius: Radius.sm))
                    HStack(spacing: Spacing.md) {
                        attachmentButton(icon: "photo.fill", label: "Photo", kind: .teal)
                        attachmentButton(icon: "mappin", label: "Location", kind: .gold)
                        attachmentButton(icon: "face.smiling", label: "Feeling", kind: .terracotta)
                        Spacer()
                    }
                    ClayButton("Share Post", systemImage: "paperplane.fill", kind: .spruce, fullWidth: true) { post() }
                        .disabled(newPostText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(newPostText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    Spacer()
                }
                .padding(Spacing.md)
            }
            .navigationTitle("New Post").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showNewPost = false }.foregroundStyle(Palette.inkSoft)
                }
            }
        }
    }

    private func post() {
        let text = newPostText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let name = authService.currentUser?.displayName ?? "You"
        let initials = authService.currentUser?.initials ?? "ME"
        let new = CommunityPost(authorName: name, authorInitials: initials,
                                placeName: "Your neighborhood", content: text,
                                timeAgo: "now", likeCount: 0, commentCount: 0, imagePlaceholder: nil)
        // Optimistic local insert for instant UI…
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { posts.insert(new, at: 0) }
        newPostText = ""
        Haptics.success()
        showNewPost = false
        // …then persist to Firestore so it's shared (when signed in).
        if let uid = authService.currentUser?.uid {
            Task { _ = await firestore.createPost(authorID: uid, authorName: name,
                                                  authorInitials: initials,
                                                  placeName: "Your neighborhood", content: text) }
        }
    }

    private func attachmentButton(icon: String, label: String, kind: ClayStyle.ClayAccentKind) -> some View {
        VStack(spacing: 6) {
            ClayIconTile(systemImage: icon, kind: kind, size: 46, radius: Radius.chip)
            Text(label).font(VType.body(11, .medium)).foregroundStyle(Palette.inkSoft)
        }
    }
}

// MARK: - Story ring (continuously rotating gradient)

private struct StoryRing: View {
    let initials: String
    let name: String
    let accent: ClayAccent
    let isYou: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rot = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(AngularGradient(colors: [accent.base, accent.gloss, accent.depth, accent.base],
                                            center: .center), lineWidth: 3.5)
                    .frame(width: 66, height: 66)
                    .rotationEffect(.degrees(rot ? 360 : 0))
                if isYou {
                    Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(accent.onColor)
                        .frame(width: 56, height: 56)
                        .background(ClayBackground(style: .accent(.spruce), radius: 28, elevation: 0.4))
                } else {
                    AvatarCircle(initials: initials, size: 56, accent: accent)
                }
            }
            .breathing(scale: 1.03, duration: 2.4)
            Text(name).font(VType.body(11, .medium)).foregroundStyle(Palette.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(width: 72)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { rot = true }
        }
    }
}

// MARK: - Post card (oversized author, animated like)

private struct PostCard: View {
    let post: CommunityPost
    let accent: ClayStyle.ClayAccentKind
    var onProfile: () -> Void = {}
    @State private var liked = false
    @State private var bump = false
    @State private var burst = false

    private var likeCount: Int { post.likeCount + (liked ? 1 : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Button(action: onProfile) {
                    HStack(spacing: Spacing.sm) {
                        AvatarCircle(initials: post.authorInitials, size: 44, accent: accent.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(post.authorName).font(VType.display(20, .semibold)).foregroundStyle(Palette.ink)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "mappin").font(.system(size: 9, weight: .bold))
                                Text(post.placeName).font(VType.body(12, .semibold))
                            }
                            .foregroundStyle(accent.accent.base)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(post.timeAgo).font(VType.body(12, .medium)).foregroundStyle(Palette.inkFaint)
            }

            Text(post.content).font(VType.body(15)).foregroundStyle(Palette.ink).lineSpacing(3)

            if post.imagePlaceholder != nil {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(accent.accent.faceGradient)
                    .frame(height: 190)
                    .overlay {
                        Image(systemName: "photo.fill").font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(accent.accent.onColor.opacity(0.7))
                    }
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    .shimmer()
            }

            HStack(spacing: Spacing.lg) {
                likeButton
                action("bubble.right", "\(post.commentCount)")
                action("arrow.turn.up.right", nil)
                Spacer()
                Image(systemName: "bookmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(Spacing.md)
        .claySurface(.surface, radius: Radius.md, elevation: 0.9)
        .overlay(alignment: .leading) {
            Capsule().fill(accent.accent.faceGradient)
                .frame(width: 4).padding(.vertical, Spacing.md).padding(.leading, 4).opacity(0.6)
        }
    }

    private var likeButton: some View {
        Button {
            liked.toggle()
            Haptics.soft()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { bump.toggle() }
            if liked {
                burst = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burst = false }
            }
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    if burst {
                        Circle().stroke(Palette.terracotta.base, lineWidth: 2)
                            .frame(width: 30, height: 30)
                            .scaleEffect(burst ? 1.8 : 0.4).opacity(burst ? 0 : 0.9)
                            .animation(.easeOut(duration: 0.55), value: burst)
                    }
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .bold))
                        .scaleEffect(bump ? 1.35 : 1)
                }
                Text("\(likeCount)").font(VType.num(13, .semibold))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(liked ? Palette.terracotta.base : Palette.inkSoft)
        }
        .buttonStyle(.plain)
    }

    private func action(_ icon: String, _ count: String?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
            if let count { Text(count).font(VType.num(12, .semibold)) }
        }
        .foregroundStyle(Palette.inkSoft)
    }
}

#Preview {
    CommunityView()
        .environment(FirestoreService())
        .environment(AuthService())
}

// MARK: - Community member profile (tap a story / post author)

struct CommunityProfile: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let accent: ClayAccent

    // Deterministic demo stats derived from the name (stable across launches).
    private var seed: Int { name.unicodeScalars.reduce(0) { $0 + Int($1.value) } }
    var level: Int { 2 + seed % 18 }
    var points: Int { 200 + (seed % 36) * 75 }
    var places: Int { 5 + seed % 45 }
    var events: Int { 1 + seed % 28 }
    var streak: Int { seed % 45 }
    var memberSince: String { ["January", "February", "March", "April", "May"][seed % 5] + " 2026" }
    var levelProgress: Double { Double((seed * 37) % 100) / 100.0 }
}

struct CommunityProfileSheet: View {
    let profile: CommunityProfile
    @Environment(\.dismiss) private var dismiss
    @State private var following = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    // Hero
                    VStack(spacing: Spacing.md) {
                        ZStack {
                            PulseHalo(color: profile.accent.base.opacity(0.5), size: 120, lineWidth: 2)
                            AvatarCircle(initials: profile.initials, size: 96, accent: profile.accent)
                                .idleFloat(distance: 4, duration: 3)
                        }
                        .frame(height: 124).padding(.top, Spacing.sm)
                        Text(profile.name).font(VType.display(28, .bold)).foregroundStyle(Palette.ink)
                        HStack(spacing: 8) {
                            Text("LEVEL \(profile.level)").font(VType.body(12, .bold)).tracking(1)
                                .foregroundStyle(profile.accent.onColor)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(ClayBackground(style: .accent(.spruce), radius: Radius.chip, elevation: 0.3))
                            Text("Member since \(profile.memberSince)")
                                .font(VType.body(12, .medium)).foregroundStyle(Palette.inkSoft)
                        }
                    }

                    // Level progress
                    VStack(spacing: Spacing.sm) {
                        HStack {
                            Text("Progress to level \(profile.level + 1)")
                                .font(VType.body(13, .semibold)).foregroundStyle(Palette.inkSoft)
                            Spacer()
                            Text("\(Int(profile.levelProgress * 100))%").font(VType.num(13, .bold))
                                .foregroundStyle(profile.accent.base)
                        }
                        ClayProgressBar(value: profile.levelProgress,
                                        gradient: [profile.accent.depth, profile.accent.base], height: 14)
                    }
                    .padding(Spacing.md).claySurface(.surface, radius: Radius.md)

                    // Stats — color-coded
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        statTile("\(profile.places)", "Places", "leaf.fill", .teal)
                        statTile("\(profile.events)", "Events", "calendar.badge.checkmark", .spruce)
                        statTile("\(profile.streak)", "Day streak", "flame.fill", .terracotta)
                        statTile("\(profile.points)", "Points", "sparkles", .gold)
                    }

                    Button { Haptics.tap(); withAnimation(.spring(response: 0.3)) { following.toggle() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: following ? "checkmark" : "person.badge.plus")
                                .font(.system(size: 15, weight: .bold))
                            Text(following ? "Following" : "Follow")
                                .font(VType.body(16, .bold))
                        }
                        .foregroundStyle(following ? Palette.spruce.base : Palette.spruce.onColor)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(ClayBackground(style: following ? .surface : .accent(.spruce), radius: Radius.md))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
            .background(VerdureBackground())
            .navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func statTile(_ value: String, _ label: String, _ icon: String, _ kind: ClayStyle.ClayAccentKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(kind.accent.base)
            Text(value).font(VType.num(26, .bold)).foregroundStyle(Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(VType.body(11, .medium)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.md)
        .claySurface(.surface, radius: Radius.md, elevation: 0.8)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(kind.accent.base.opacity(0.38), lineWidth: 1.5))
    }
}
