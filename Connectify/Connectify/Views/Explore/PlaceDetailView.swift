import SwiftUI

struct PlaceDetailView: View {
    let place: Place
    @State private var isSaved = false
    @State private var showCelebration = false
    @State private var celebrationPoints = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(GameStateManager.self) private var gameState
    @Environment(PlacesAPIService.self) private var placesService

    private var collectible: CollectiblePlace? {
        placesService.collectible(for: place) ?? SampleData.collectible(for: place)
    }

    private var isCollected: Bool {
        guard let c = collectible else { return false }
        return gameState.isCollected(c.id)
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero image
                    ZStack(alignment: .bottomLeading) {
                        PlacePlaceholder(
                            icon: place.imagePlaceholder,
                            color: place.accentColor,
                            height: 280
                        )

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 0))

                        VStack(alignment: .leading, spacing: 6) {
                            if let c = collectible {
                                HStack(spacing: 8) {
                                    RarityBadge(rarity: c.rarity)
                                    if isCollected {
                                        HStack(spacing: 3) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 11))
                                            Text("COLLECTED")
                                                .font(CFont.label(10))
                                                .tracking(0.5)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.connectifyGreen.opacity(0.2))
                                        .foregroundStyle(Color.connectifyGreen)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }
                            }

                            HStack(spacing: 6) {
                                Image(systemName: place.category.icon)
                                    .font(.system(size: 11))
                                Text(place.category.rawValue.uppercased())
                                    .font(CFont.label(11))
                                    .tracking(0.8)
                            }
                            .foregroundStyle(.white.opacity(0.8))

                            Text(place.name)
                                .font(CFont.display(28))
                                .foregroundStyle(.white)
                        }
                        .padding(Spacing.lg)
                    }

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Quick stats
                        HStack(spacing: 0) {
                            quickStat(value: place.distance, label: "Away", icon: "location.fill")
                            Divider().frame(height: 36)
                            quickStat(value: String(format: "%.1f", place.rating), label: "\(place.reviewCount) reviews", icon: "star.fill")
                            Divider().frame(height: 36)
                            if let c = collectible {
                                quickStat(
                                    value: "\(c.pointValue)",
                                    label: c.rarity.rawValue,
                                    icon: c.rarity.icon,
                                    tint: c.rarity.color
                                )
                            } else {
                                quickStat(value: place.isFeatured ? "Yes" : "—", label: "Featured", icon: "sparkles")
                            }
                        }
                        .padding(.vertical, Spacing.md)
                        .background(.greenCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                        // Description
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("About")
                                .font(CFont.headline(17))
                                .foregroundStyle(.primaryText)

                            Text(place.shortDescription)
                                .font(CFont.body(15))
                                .foregroundStyle(.secondaryText)
                                .lineSpacing(4)

                            Text("More details will be available once the backend is connected. This will include hours, amenities, accessibility info, and user-submitted photos.")
                                .font(CFont.body(14))
                                .foregroundStyle(.tertiaryText)
                                .padding(.top, Spacing.xs)
                        }

                        // Actions
                        VStack(spacing: Spacing.sm) {
                            collectButton

                            ConnectifyButton(title: "Get Directions", icon: "arrow.triangle.turn.up.right.diamond.fill", style: .secondary) {
                                // Placeholder: open Maps
                            }

                            HStack(spacing: Spacing.sm) {
                                ConnectifyButton(title: isSaved ? "Saved" : "Save", icon: isSaved ? "bookmark.fill" : "bookmark", style: .secondary) {
                                    withAnimation(.spring(response: 0.3)) {
                                        isSaved.toggle()
                                    }
                                }
                            }
                        }

                        // Nearby events placeholder
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Upcoming Events Here")
                                .font(CFont.headline(17))
                                .foregroundStyle(.primaryText)

                            Text("No upcoming events at this location.")
                                .font(CFont.body(14))
                                .foregroundStyle(.tertiaryText)
                                .padding(.vertical, Spacing.lg)
                                .frame(maxWidth: .infinity)
                                .background(.cardSurface)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        }
                    }
                    .padding(Spacing.md)
                }
            }
            .background(.pageSurface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Placeholder: share
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .tint(.primaryText)
                }
            }

            // Celebration overlay
            if showCelebration, let c = collectible {
                CollectionCelebrationView(
                    collectible: c,
                    pointsEarned: celebrationPoints
                ) {
                    withAnimation { showCelebration = false }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Collect Button

    @ViewBuilder
    private var collectButton: some View {
        if let c = collectible {
            if isCollected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.connectifyGreen)
                    Text("Collected")
                        .font(CFont.headline(16))
                        .foregroundStyle(.primaryText)
                    Spacer()
                    PointsBadge(points: c.pointValue, prefix: "")
                }
                .padding(Spacing.md)
                .background(.greenSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            } else if c.isNearbyStatic {
                ConnectifyButton(
                    title: "Collect — +\(c.pointValue) pts",
                    icon: "plus.circle.fill"
                ) {
                    celebrationPoints = gameState.collectPlace(c)
                    withAnimation(.spring(response: 0.4)) {
                        showCelebration = true
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .foregroundStyle(.tertiaryText)
                    Text("Too far to collect")
                        .font(CFont.headline(15))
                        .foregroundStyle(.secondaryText)
                    Spacer()
                    Text(place.distance)
                        .font(CFont.caption(13))
                        .foregroundStyle(.tertiaryText)
                    PointsBadge(points: c.pointValue)
                }
                .padding(Spacing.md)
                .background(.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            }
        }
    }

    private func quickStat(value: String, label: String, icon: String, tint: Color = Color.connectifyGreen) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
                Text(value)
                    .font(CFont.headline(16))
                    .foregroundStyle(.primaryText)
            }
            Text(label)
                .font(CFont.caption(11))
                .foregroundStyle(.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        PlaceDetailView(place: SampleData.places[0])
            .environment(GameStateManager())
            .environment(PlacesAPIService())
    }
}
