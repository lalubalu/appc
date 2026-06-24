import SwiftUI

struct CollectionView: View {
    @Environment(GameStateManager.self) private var gameState
    @Environment(PlacesAPIService.self) private var placesService
    @State private var showRewardsStore = false
    @State private var selectedCollectible: CollectiblePlace? = nil
    @State private var filterRarity: PlaceRarity? = nil

    private var allCollectibles: [CollectiblePlace] {
        placesService.collectiblePlaces.isEmpty ? SampleData.collectiblePlaces : placesService.collectiblePlaces
    }
    private var displayedPlaces: [CollectiblePlace] {
        guard let rarity = filterRarity else { return allCollectibles }
        return allCollectibles.filter { $0.rarity == rarity }
    }
    private var progress: Double { gameState.collectionProgress(total: allCollectibles.count) }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.xl) {
                    vaultHero.dramaticRise(index: 0)
                    rarityFilters.riseIn(index: 1)
                    categoryRail.riseIn(index: 2)
                    vaultGrid.riseIn(index: 3)
                }
                .padding(.top, Spacing.lg)
                .padding(.bottom, 110)
            }
            .background(VerdureBackground())
            .sheet(isPresented: $showRewardsStore) { RewardsStoreView().environment(gameState) }
            .sheet(item: $selectedCollectible) { collectible in
                CollectibleDetailSheet(collectible: collectible)
                    .environment(gameState)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Vault hero (oversized count-up + 3D core + pulse)

    private var vaultHero: some View {
        VStack(spacing: Spacing.md) {
            KickerLabel(text: "The Vault", color: Palette.gold.base, dot: Palette.gold.base)

            ZStack {
                PulseHalo(color: Palette.teal.base.opacity(0.6), size: 210, lineWidth: 2)
                PulseHalo(color: Palette.gold.base.opacity(0.4), size: 150, lineWidth: 2)
                FloatingBlob(color: Palette.teal.base.opacity(0.35), size: 130, delay: 0).offset(x: -90, y: -10)
                FloatingBlob(color: Palette.gold.base.opacity(0.3), size: 100, delay: 0.7).offset(x: 95, y: 20)
                MedallionHero(size: 150, interactive: false)
            }
            .frame(height: 180)

            VStack(spacing: 2) {
                Text("POINT BALANCE").font(VType.body(11, .bold)).tracking(2)
                    .foregroundStyle(Palette.inkSoft)
                CountUp(value: gameState.pointsBalance)
                    .font(VType.num(72, .bold)).monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .breathing(scale: 1.03, duration: 3)
                Text("Lifetime · \(gameState.lifetimePoints) pts earned")
                    .font(VType.num(12, .medium)).foregroundStyle(Palette.inkFaint)
            }

            HStack(spacing: Spacing.md) {
                NeonProgressRing(progress: progress, size: 78, lineWidth: 6, showLabel: false)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(gameState.totalCollected)").font(VType.num(22, .bold)).foregroundStyle(Palette.ink)
                            Text("of \(allCollectibles.count)").font(VType.body(9, .medium)).foregroundStyle(Palette.inkSoft)
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Int(progress * 100))% collected")
                        .font(VType.display(17, .semibold)).foregroundStyle(Palette.ink)
                    ClayButton("Redeem rewards", systemImage: "gift.fill", kind: .gold) {
                        showRewardsStore = true
                    }
                    .breathing(scale: 1.02, duration: 2.4)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity)
            .claySurface(.surface, radius: Radius.lg, elevation: 1.1)
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Rarity filters

    private var rarityFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                CategoryPill(label: "All", icon: "square.grid.2x2.fill",
                             tint: Palette.spruce.base, isSelected: filterRarity == nil) {
                    withAnimation(.spring(response: 0.35)) { filterRarity = nil }
                }
                ForEach(PlaceRarity.allCases) { rarity in
                    CategoryPill(label: rarity.rawValue, icon: rarity.icon, tint: rarity.accent.base,
                                 isSelected: filterRarity == rarity) {
                        withAnimation(.spring(response: 0.35)) { filterRarity = rarity }
                    }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 2)
        }
    }

    // MARK: - Category rail

    private var categoryRail: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "By Category").padding(.horizontal, Spacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    let catStats = gameState.collectionsByCategory(from: allCollectibles)
                    ForEach(PlaceCategory.allCases) { cat in
                        let stats = catStats[cat] ?? (0, 0)
                        CategoryCollectionCard(category: cat, collected: stats.collected, total: stats.total)
                    }
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, 4)
            }
        }
    }

    // MARK: - Staggered masonry gem grid

    private var vaultGrid: some View {
        let items = displayedPlaces
        let left = items.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let right = items.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Collectidex").padding(.horizontal, Spacing.md)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    ForEach(left) { gemTile($0) }
                }
                VStack(spacing: 14) {
                    ForEach(right) { gemTile($0) }
                }
                .padding(.top, 30)
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private func gemTile(_ c: CollectiblePlace) -> some View {
        GemTile(collectible: c, isCollected: gameState.isCollected(c.id)) {
            Haptics.soft(); selectedCollectible = c
        }
    }
}

// MARK: - Gem tile (floating, glows when collected)

private struct GemTile: View {
    let collectible: CollectiblePlace
    let isCollected: Bool
    let onTap: () -> Void

    private var height: CGFloat {
        switch collectible.rarity {
        case .common: return 120
        case .uncommon: return 138
        case .rare: return 158
        case .legendary: return 182
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    if isCollected {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(collectible.rarity.accent.faceGradient)
                            .frame(height: height)
                            .overlay {
                                Image(systemName: collectible.place.imagePlaceholder)
                                    .font(.system(size: height * 0.34, weight: .semibold))
                                    .foregroundStyle(collectible.rarity.accent.onColor.opacity(0.92))
                            }
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                                    .shadow(color: collectible.rarity.accent.depth, radius: 2).padding(8)
                            }
                            .shimmer()
                            .shadow(color: collectible.rarity.accent.base.opacity(0.5), radius: 14, x: 0, y: 8)
                    } else {
                        ClayBackground(style: .inset, radius: Radius.sm)
                            .frame(height: height)
                            .overlay {
                                VStack(spacing: 5) {
                                    Image(systemName: "questionmark").font(.system(size: 24, weight: .bold))
                                    Text("Undiscovered").font(VType.body(9, .semibold)).tracking(0.5)
                                }
                                .foregroundStyle(Palette.inkFaint)
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                Text(isCollected ? collectible.place.name : "???")
                    .font(VType.display(14, .semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    RarityDot(rarity: collectible.rarity, size: 8)
                    Spacer()
                    PointsBadge(points: collectible.pointValue, prefix: isCollected ? "" : "+",
                                kind: collectible.rarity.clayKind)
                }
            }
            .padding(10)
            .claySurface(.surface, radius: Radius.md, elevation: isCollected ? 0.95 : 0.6)
            // Rarity-tinted border so each tier reads distinctly (Vishvak/Rishit feedback).
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(collectible.rarity.accent.base.opacity(isCollected ? 0.6 : 0.28),
                                  lineWidth: isCollected ? 2 : 1.5)
            )
        }
        .buttonStyle(Card3DButtonStyle())
        .idleFloat(distance: isCollected ? 4 : 0, duration: 3.2)
    }
}

// MARK: - Category collection card

private struct CategoryCollectionCard: View {
    let category: PlaceCategory
    let collected: Int
    let total: Int
    private var progress: Double { total > 0 ? Double(collected) / Double(total) : 0 }

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle().stroke(Palette.surfaceSink, lineWidth: 4).frame(width: 46, height: 46)
                Circle().trim(from: 0, to: progress)
                    .stroke(category.accent.base, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 46, height: 46).rotationEffect(.degrees(-90))
                Image(systemName: category.icon).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(category.accent.base)
            }
            Text(category.rawValue).font(VType.body(11, .semibold)).foregroundStyle(Palette.ink)
            Text("\(collected)/\(total)").font(VType.num(10, .bold)).foregroundStyle(Palette.inkSoft)
        }
        .frame(width: 88)
        .padding(.vertical, Spacing.md)
        .claySurface(.surface, radius: Radius.sm, elevation: 0.6)
    }
}

// MARK: - Collectible detail sheet

private struct CollectibleDetailSheet: View {
    let collectible: CollectiblePlace
    @Environment(GameStateManager.self) private var gameState
    @Environment(\.dismiss) private var dismiss
    @State private var justCollected = false
    @State private var animatedPoints = 0

    private var isCollected: Bool { gameState.isCollected(collectible.id) || justCollected }
    private var kind: ClayStyle.ClayAccentKind { collectible.rarity.clayKind }

    var body: some View {
        ZStack {
            VerdureBackground()
            VStack(spacing: Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(isCollected ? AnyShapeStyle(kind.accent.faceGradient) : AnyShapeStyle(Palette.surfaceSink))
                        .frame(height: 150)
                        .overlay {
                            Image(systemName: collectible.place.imagePlaceholder)
                                .font(.system(size: 60, weight: .semibold))
                                .foregroundStyle(isCollected ? kind.accent.onColor.opacity(0.9) : Palette.inkFaint)
                        }
                    if justCollected {
                        Text("COLLECTED!").font(VType.display(22, .bold)).foregroundStyle(.white)
                            .shadow(radius: 4).transition(.scale.combined(with: .opacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .padding(.horizontal, Spacing.md)

                VStack(spacing: Spacing.sm) {
                    HStack {
                        RarityBadge(rarity: collectible.rarity, size: .large)
                        Spacer()
                        if justCollected {
                            Text("+\(animatedPoints) pts").font(VType.num(22, .bold))
                                .foregroundStyle(Palette.gold.base).contentTransition(.numericText())
                        } else {
                            PointsBadge(points: collectible.pointValue, prefix: isCollected ? "" : "+")
                        }
                    }
                    Text(isCollected ? collectible.place.name : "??? Unknown Place")
                        .font(VType.display(22, .semibold)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(isCollected ? collectible.place.shortDescription
                         : "Visit this \(collectible.place.category.rawValue.lowercased()) to collect it and reveal its details.")
                        .font(VType.body(14)).foregroundStyle(Palette.inkSoft)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: Spacing.md) {
                        Label(collectible.place.distance, systemImage: "location.fill")
                        Label(collectible.place.category.rawValue, systemImage: collectible.place.category.icon)
                    }
                    .font(VType.num(12, .semibold)).foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.md)

                if isCollected {
                    ClayButton("Collected", systemImage: "checkmark.seal.fill", kind: .ghost, fullWidth: true) {}
                        .disabled(true).opacity(0.7).padding(.horizontal, Spacing.md)
                } else if collectible.isNearbyStatic {
                    ClayButton("Collect This Place", systemImage: "plus.circle.fill", kind: .spruce, fullWidth: true) { collect() }
                        .padding(.horizontal, Spacing.md)
                } else {
                    ClayButton("Too far · \(collectible.place.distance)", systemImage: "location.slash.fill",
                               kind: .ghost, fullWidth: true) {}
                        .disabled(true).opacity(0.55).padding(.horizontal, Spacing.md)
                }
                Spacer()
            }
            .padding(.top, Spacing.lg)
        }
    }

    private func collect() {
        let pts = gameState.collectPlace(collectible)
        Haptics.success()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { justCollected = true }
        withAnimation(.easeOut(duration: 0.8)) { animatedPoints = pts }
    }
}

#Preview {
    CollectionView()
        .environment(GameStateManager())
        .environment(PlacesAPIService())
}
