import SwiftUI

struct CollectionView: View {
    @Environment(GameStateManager.self) private var gameState
    @State private var showRewardsStore = false
    @State private var selectedCollectible: CollectiblePlace? = nil
    @State private var filterRarity: PlaceRarity? = nil

    private var displayedPlaces: [CollectiblePlace] {
        guard let rarity = filterRarity else { return SampleData.collectiblePlaces }
        return SampleData.collectiblePlaces.filter { $0.rarity == rarity }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    // Points wallet
                    walletCard

                    // Collection progress
                    progressSection

                    // Category breakdown
                    categoryBreakdown

                    // Rarity filter
                    rarityFilters

                    // Collection grid
                    collectionGrid
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(.pageSurface)
            .navigationTitle("Collection")
            .sheet(isPresented: $showRewardsStore) {
                RewardsStoreView()
                    .environment(gameState)
            }
            .sheet(item: $selectedCollectible) { collectible in
                CollectibleDetailSheet(collectible: collectible)
                    .environment(gameState)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Wallet Card

    private var walletCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("POINT BALANCE")
                        .font(CFont.label(11))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))

                    Text("\(gameState.pointsBalance)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text("Lifetime: \(gameState.lifetimePoints) pts earned")
                        .font(CFont.caption(12))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.9))

                    Button("Rewards") {
                        showRewardsStore = true
                    }
                    .font(CFont.label(11))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.white)
                    .clipShape(Capsule())
                }
            }
            .padding(Spacing.lg)
            .background(
                LinearGradient(
                    colors: [Color.connectifyGreen, Color.accentMint, Color.connectifyGreen.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        HStack(spacing: Spacing.lg) {
            // Big progress ring
            VStack(spacing: 8) {
                ProgressRing(
                    progress: gameState.collectionProgress(total: SampleData.collectiblePlaces.count),
                    size: 90,
                    lineWidth: 6
                )
                Text("\(gameState.totalCollected)/\(SampleData.collectiblePlaces.count)")
                    .font(CFont.headline(15))
                    .foregroundStyle(.primaryText)
                Text("Collected")
                    .font(CFont.caption(12))
                    .foregroundStyle(.secondaryText)
            }

            // Rarity breakdown
            VStack(alignment: .leading, spacing: 10) {
                ForEach(PlaceRarity.allCases) { rarity in
                    let count = SampleData.collectiblePlaces.filter { $0.rarity == rarity }.count
                    let collected = SampleData.collectiblePlaces.filter {
                        $0.rarity == rarity && gameState.isCollected($0.id)
                    }.count

                    HStack(spacing: 8) {
                        RarityDot(rarity: rarity)
                        Text(rarity.rawValue)
                            .font(CFont.caption(13))
                            .foregroundStyle(.primaryText)
                        Spacer()
                        Text("\(collected)/\(count)")
                            .font(CFont.label(12))
                            .foregroundStyle(.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Spacing.md)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(.subtleBorder, lineWidth: 0.5)
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Category Breakdown

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "By Category")
                .padding(.horizontal, Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    let catStats = gameState.collectionsByCategory(from: SampleData.collectiblePlaces)
                    ForEach(PlaceCategory.allCases) { cat in
                        let stats = catStats[cat] ?? (0, 0)
                        CategoryCollectionCard(
                            category: cat,
                            collected: stats.collected,
                            total: stats.total
                        )
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    // MARK: - Rarity Filters

    private var rarityFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(label: "All", selected: filterRarity == nil) {
                    withAnimation(.spring(response: 0.3)) { filterRarity = nil }
                }
                ForEach(PlaceRarity.allCases) { rarity in
                    filterPill(
                        label: rarity.rawValue,
                        icon: rarity.icon,
                        tint: rarity.color,
                        selected: filterRarity == rarity
                    ) {
                        withAnimation(.spring(response: 0.3)) { filterRarity = rarity }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private func filterPill(label: String, icon: String? = nil, tint: Color = .connectifyGreen, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                }
                Text(label)
                    .font(CFont.caption(12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? tint.opacity(0.15) : .cardSurface)
            .foregroundStyle(selected ? tint : .secondaryText)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(selected ? tint.opacity(0.4) : .subtleBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Collection Grid

    private var collectionGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Collectidex")
                .padding(.horizontal, Spacing.md)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(displayedPlaces) { collectible in
                    CollectionCard(
                        collectible: collectible,
                        isCollected: gameState.isCollected(collectible.id)
                    )
                    .onTapGesture {
                        selectedCollectible = collectible
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }
}

// MARK: - Collection Card

private struct CollectionCard: View {
    let collectible: CollectiblePlace
    let isCollected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image area
            ZStack {
                PlacePlaceholder(
                    icon: collectible.place.imagePlaceholder,
                    color: isCollected ? collectible.place.accentColor : .gray,
                    height: 110
                )
                .grayscale(isCollected ? 0 : 1)
                .opacity(isCollected ? 1 : 0.3)

                if !isCollected {
                    // Mystery overlay
                    VStack(spacing: 4) {
                        Image(systemName: "questionmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.tertiaryText)
                        Text("Undiscovered")
                            .font(CFont.label(9))
                            .foregroundStyle(.tertiaryText)
                    }
                } else {
                    // Collected checkmark
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.connectifyGreen)
                                .background(Circle().fill(.cardSurface).padding(2))
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    RarityDot(rarity: collectible.rarity)
                    Text(isCollected ? collectible.place.name : "???")
                        .font(CFont.headline(13))
                        .foregroundStyle(.primaryText)
                        .lineLimit(1)
                }

                HStack {
                    RarityBadge(rarity: collectible.rarity, size: .small)
                    Spacer()
                    PointsBadge(points: collectible.pointValue, prefix: isCollected ? "" : "+")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(
                    isCollected ? Color.connectifyGreen.opacity(0.3) : .subtleBorder,
                    lineWidth: isCollected ? 1.5 : 0.5
                )
        }
        // Legendary glow
        .shadow(color: collectible.rarity.color.opacity(collectible.rarity.glowOpacity), radius: 8, y: 2)
    }
}

// MARK: - Category Collection Card

private struct CategoryCollectionCard: View {
    let category: PlaceCategory
    let collected: Int
    let total: Int

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(collected) / Double(total)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.subtleBorder, lineWidth: 3)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(category.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))

                Image(systemName: category.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(category.tint)
            }

            Text(category.rawValue)
                .font(CFont.caption(11))
                .foregroundStyle(.primaryText)

            Text("\(collected)/\(total)")
                .font(CFont.label(10))
                .foregroundStyle(.secondaryText)
        }
        .frame(width: 80)
        .padding(.vertical, Spacing.sm)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(.subtleBorder, lineWidth: 0.5)
        }
    }
}

// MARK: - Collectible Detail Sheet

private struct CollectibleDetailSheet: View {
    let collectible: CollectiblePlace
    @Environment(GameStateManager.self) private var gameState
    @Environment(\.dismiss) private var dismiss
    @State private var justCollected = false
    @State private var animatedPoints = 0

    private var isCollected: Bool {
        gameState.isCollected(collectible.id) || justCollected
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Header
            PlacePlaceholder(
                icon: collectible.place.imagePlaceholder,
                color: isCollected ? collectible.place.accentColor : .gray,
                height: 140
            )
            .grayscale(isCollected ? 0 : 0.8)
            .opacity(isCollected ? 1 : 0.4)
            .overlay {
                if justCollected {
                    VStack {
                        Text("COLLECTED!")
                            .font(CFont.title(20))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .padding(.horizontal, Spacing.md)

            VStack(spacing: Spacing.sm) {
                HStack {
                    RarityBadge(rarity: collectible.rarity, size: .large)
                    Spacer()
                    if justCollected {
                        Text("+\(animatedPoints) pts")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentAmber)
                            .contentTransition(.numericText())
                    } else {
                        PointsBadge(points: collectible.pointValue, prefix: isCollected ? "" : "+")
                    }
                }

                Text(isCollected ? collectible.place.name : "??? Unknown Place")
                    .font(CFont.title(20))
                    .foregroundStyle(.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isCollected {
                    Text(collectible.place.shortDescription)
                        .font(CFont.body(14))
                        .foregroundStyle(.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Visit this \(collectible.place.category.rawValue.lowercased()) location to collect it and reveal its details.")
                        .font(CFont.body(14))
                        .foregroundStyle(.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: Spacing.md) {
                    Label(collectible.place.distance, systemImage: "location.fill")
                    Label(collectible.place.category.rawValue, systemImage: collectible.place.category.icon)
                }
                .font(CFont.caption(12))
                .foregroundStyle(.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.md)

            // Action button
            if isCollected {
                ConnectifyButton(title: "Collected", icon: "checkmark.circle.fill", style: .secondary) {}
                    .disabled(true)
                    .opacity(0.6)
                    .padding(.horizontal, Spacing.md)
            } else if collectible.isNearby {
                ConnectifyButton(title: "Collect This Place", icon: "plus.circle.fill") {
                    collect()
                }
                .padding(.horizontal, Spacing.md)
            } else {
                ConnectifyButton(title: "Too Far — \(collectible.place.distance) away", icon: "location.slash.fill", style: .secondary) {}
                    .disabled(true)
                    .opacity(0.5)
                    .padding(.horizontal, Spacing.md)
            }

            Spacer()
        }
        .padding(.top, Spacing.md)
    }

    private func collect() {
        let pts = gameState.collectPlace(collectible)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            justCollected = true
        }
        // Animate points counting up
        withAnimation(.easeOut(duration: 0.8)) {
            animatedPoints = pts
        }
    }
}

#Preview {
    CollectionView()
        .environment(GameStateManager())
}
