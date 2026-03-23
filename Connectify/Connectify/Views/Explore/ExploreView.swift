import SwiftUI

struct ExploreView: View {
    @State private var searchText = ""
    @State private var selectedCategory: PlaceCategory? = nil
    @State private var showGemDetail = false

    private var filteredPlaces: [Place] {
        var result = SampleData.places
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Daily Gem
                    dailyGemSection

                    // Active Challenges
                    challengeSection

                    // Category Filters
                    categoryFilters

                    // Places Grid
                    placesSection
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(.pageSurface)
            .navigationTitle("Explore")
            .searchable(text: $searchText, prompt: "Search places...")
        }
    }

    // MARK: - Daily Gem

    private var dailyGemSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Daily Gem", action: nil)
                .padding(.horizontal, Spacing.md)

            let gem = SampleData.dailyGem
            Button { showGemDetail = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    // Image area
                    ZStack(alignment: .topLeading) {
                        PlacePlaceholder(
                            icon: gem.place.imagePlaceholder,
                            color: gem.place.accentColor,
                            height: 180
                        )

                        // Badge
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 11, weight: .bold))
                            Text("TODAY'S GEM")
                                .font(CFont.label(10))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(12)
                    }

                    // Info
                    VStack(alignment: .leading, spacing: 6) {
                        Text(gem.headline)
                            .font(CFont.headline(18))
                            .foregroundStyle(.primaryText)

                        Text(gem.reason)
                            .font(CFont.body(14))
                            .foregroundStyle(.secondaryText)
                            .lineLimit(2)

                        HStack(spacing: Spacing.md) {
                            Label(gem.place.distance, systemImage: "location.fill")
                            Label(String(format: "%.1f", gem.place.rating), systemImage: "star.fill")
                        }
                        .font(CFont.caption(12))
                        .foregroundStyle(.tertiaryText)
                        .padding(.top, 2)
                    }
                    .padding(Spacing.md)
                }
                .background(.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(.subtleBorder, lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.md)
            .sheet(isPresented: $showGemDetail) {
                PlaceDetailView(place: gem.place)
            }
        }
    }

    // MARK: - Challenges

    private var challengeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Active Challenges", action: "See All")
                .padding(.horizontal, Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SampleData.challenges) { challenge in
                        ChallengeCard(challenge: challenge)
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    // MARK: - Category Filters

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryPill(label: "All", icon: "square.grid.2x2.fill", tint: .connectifyGreen, isSelected: selectedCategory == nil) {
                    withAnimation(.spring(response: 0.3)) { selectedCategory = nil }
                }
                ForEach(PlaceCategory.allCases) { cat in
                    CategoryPill(label: cat.rawValue, icon: cat.icon, tint: cat.tint, isSelected: selectedCategory == cat) {
                        withAnimation(.spring(response: 0.3)) { selectedCategory = cat }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Places

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: selectedCategory?.rawValue ?? "Nearby Places", action: "Filter")
                .padding(.horizontal, Spacing.md)

            if filteredPlaces.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No places found",
                    subtitle: "Try adjusting your filters or search terms."
                )
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredPlaces) { place in
                        NavigationLink(value: place) {
                            PlaceRow(place: place)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
        .navigationDestination(for: Place.self) { place in
            PlaceDetailView(place: place)
        }
    }
}

// MARK: - Challenge Card

private struct ChallengeCard: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: challenge.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.connectifyGreen)
                Spacer()
                ProgressRing(progress: challenge.progress, size: 36, lineWidth: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title)
                    .font(CFont.headline(15))
                    .foregroundStyle(.primaryText)

                Text(challenge.description)
                    .font(CFont.caption(12))
                    .foregroundStyle(.secondaryText)
                    .lineLimit(2)
            }

            HStack {
                XPBadge(xp: challenge.xpReward)
                Spacer()
                Text("\(challenge.daysRemaining)d left")
                    .font(CFont.label(11))
                    .foregroundStyle(.tertiaryText)
            }
        }
        .padding(Spacing.md)
        .frame(width: 200)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(.subtleBorder, lineWidth: 0.5)
        }
    }
}

// MARK: - Place Row

private struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: Spacing.md) {
            PlacePlaceholder(icon: place.imagePlaceholder, color: place.accentColor, height: 80)
                .frame(width: 80)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(place.category.rawValue)
                        .font(CFont.label(10))
                        .foregroundStyle(place.accentColor)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    if place.isFeatured {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.accentAmber)
                    }
                }

                Text(place.name)
                    .font(CFont.headline(16))
                    .foregroundStyle(.primaryText)

                Text(place.shortDescription)
                    .font(CFont.caption(13))
                    .foregroundStyle(.secondaryText)
                    .lineLimit(2)

                HStack(spacing: Spacing.md) {
                    Label(place.distance, systemImage: "location.fill")
                    Label(String(format: "%.1f (%d)", place.rating, place.reviewCount), systemImage: "star.fill")
                }
                .font(CFont.caption(11))
                .foregroundStyle(.tertiaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiaryText)
        }
        .padding(Spacing.sm)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(.subtleBorder, lineWidth: 0.5)
        }
    }
}

#Preview {
    ExploreView()
}
