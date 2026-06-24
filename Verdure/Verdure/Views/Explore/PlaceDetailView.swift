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
    private var kind: ClayStyle.ClayAccentKind { place.category.clayKind }

    var body: some View {
        ZStack {
            VerdureBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    hero
                    quickStats
                    aboutSection
                    actions
                    eventsSection
                }
                .padding(Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                    }
                    .tint(Palette.ink)
                }
            }

            if showCelebration, let c = collectible {
                CollectionCelebrationView(collectible: c, pointsEarned: celebrationPoints) {
                    withAnimation { showCelebration = false }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(kind.accent.faceGradient)
                .frame(height: 250)
                .overlay {
                    Image(systemName: place.imagePlaceholder)
                        .font(.system(size: 150, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.16))
                        .rotationEffect(.degrees(-8))
                        .offset(x: 70, y: 10)
                        .clipped()
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .shadow(color: kind.accent.depth.opacity(0.5), radius: 24, x: 10, y: 14)
                .parallaxTilt(magnitude: 5, shadow: false)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let c = collectible { RarityBadge(rarity: c.rarity) }
                    if isCollected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 11, weight: .bold))
                            Text("COLLECTED").font(VType.body(10, .bold)).tracking(0.6)
                        }
                        .foregroundStyle(Palette.teal.onColor)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(ClayBackground(style: .accent(.teal), radius: Radius.chip, elevation: 0.3))
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: place.category.icon).font(.system(size: 11, weight: .bold))
                    Text(place.category.rawValue.uppercased()).font(VType.body(11, .bold)).tracking(0.8)
                }
                .foregroundStyle(kind.accent.onColor.opacity(0.85))
                Text(place.name)
                    .font(VType.display(30, .bold))
                    .foregroundStyle(kind.accent.onColor)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .shadow(color: kind.accent.depth.opacity(0.4), radius: 4, x: 1, y: 2)
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: - Quick stats

    private var quickStats: some View {
        HStack(spacing: 10) {
            statWell(place.distance, "Away", "location.fill", Palette.teal.base)
            statWell(String(format: "%.1f", place.rating), "\(place.reviewCount) reviews", "star.fill", Palette.gold.base)
            if let c = collectible {
                statWell("\(c.pointValue)", c.rarity.rawValue, c.rarity.icon, c.rarity.accent.base)
            } else {
                statWell(place.isFeatured ? "Yes" : "—", "Featured", "sparkles", Palette.spruce.base)
            }
        }
    }

    private func statWell(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
                Text(value).font(VType.num(16, .bold)).foregroundStyle(Palette.ink)
            }
            Text(label).font(VType.body(11, .medium)).foregroundStyle(Palette.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(ClayBackground(style: .inset, radius: Radius.sm))
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("About").font(VType.display(20, .semibold)).foregroundStyle(Palette.ink)
            Text(place.shortDescription)
                .font(VType.body(15)).foregroundStyle(Palette.inkSoft).lineSpacing(4)

            Divider().background(Palette.surfaceShadow.opacity(0.4))

            // Hours
            HStack(spacing: 10) {
                Image(systemName: "clock.fill").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(kind.accent.base).frame(width: 22)
                Text("Hours").font(VType.body(13, .semibold)).foregroundStyle(Palette.inkSoft)
                Spacer()
                Text(place.openHours).font(VType.body(13, .semibold)).foregroundStyle(Palette.ink)
            }

            // Amenities
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Amenities").font(VType.body(13, .semibold)).foregroundStyle(Palette.inkSoft)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                    ForEach(place.amenities, id: \.label) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.icon).font(.system(size: 12, weight: .bold))
                                .foregroundStyle(kind.accent.base)
                            Text(item.label).font(VType.body(12.5, .medium)).foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(ClayBackground(style: .inset, radius: Radius.chip))
                    }
                }
            }

            // Accessibility
            HStack(spacing: 10) {
                Image(systemName: "figure.roll").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(kind.accent.base).frame(width: 22)
                Text(place.accessibilityNote).font(VType.body(13, .medium)).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .claySurface(.surface, radius: Radius.md)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Spacing.sm) {
            collectButton
            HStack(spacing: Spacing.sm) {
                ClayButton("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                           kind: .teal, fullWidth: true) {}
                ClayButton(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark",
                           kind: .ghost, fullWidth: true) {
                    withAnimation(.spring(response: 0.3)) { isSaved.toggle() }
                }
            }
        }
    }

    @ViewBuilder
    private var collectButton: some View {
        if let c = collectible {
            if isCollected {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.teal.base)
                        .font(.system(size: 18, weight: .bold))
                    Text("Collected").font(VType.body(16, .bold)).foregroundStyle(Palette.ink)
                    Spacer()
                    PointsBadge(points: c.pointValue, prefix: "")
                }
                .padding(Spacing.md)
                .claySurface(.surface, radius: Radius.md)
            } else if c.isNearbyStatic {
                ClayButton("Collect  ·  +\(c.pointValue) pts", systemImage: "plus.circle.fill",
                           kind: .spruce, fullWidth: true) {
                    celebrationPoints = gameState.collectPlace(c)
                    Haptics.success()
                    withAnimation(.spring(response: 0.4)) { showCelebration = true }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "location.slash.fill").foregroundStyle(Palette.inkFaint)
                    Text("Too far to collect").font(VType.body(15, .semibold)).foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Text(place.distance).font(VType.num(13, .semibold)).foregroundStyle(Palette.inkFaint)
                    PointsBadge(points: c.pointValue)
                }
                .padding(Spacing.md)
                .background(ClayBackground(style: .inset, radius: Radius.md))
            }
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Upcoming Events Here").font(VType.display(20, .semibold)).foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                Image(systemName: "calendar").foregroundStyle(Palette.inkFaint)
                Text("No upcoming events at this location.")
                    .font(VType.body(14)).foregroundStyle(Palette.inkSoft)
                Spacer()
            }
            .padding(Spacing.md)
            .background(ClayBackground(style: .inset, radius: Radius.md))
        }
    }
}

#Preview {
    NavigationStack {
        PlaceDetailView(place: SampleData.places[0])
            .environment(GameStateManager())
            .environment(PlacesAPIService())
    }
}

// MARK: - Derived place info (category-based, deterministic — stands in for backend data)

extension Place {
    /// Opening hours inferred from the place category.
    var openHours: String {
        switch category {
        case .parks, .gardens:        return "6:00 AM – 10:00 PM"
        case .trails, .scenic:        return "Dawn to dusk"
        case .playgrounds:            return "8:00 AM – 8:00 PM"
        case .waterfront:             return "Open 24 hours"
        case .sports:                 return "7:00 AM – 9:00 PM"
        case .community:              return "9:00 AM – 6:00 PM"
        }
    }

    /// Amenity chips (SF Symbol + label) inferred from category.
    var amenities: [(icon: String, label: String)] {
        switch category {
        case .parks:
            return [("figure.walk", "Walking paths"), ("car.fill", "Parking"),
                    ("toilet.fill", "Restrooms"), ("dog.fill", "Dog friendly")]
        case .trails, .scenic:
            return [("car.fill", "Trailhead parking"), ("mountain.2.fill", "Scenic views"),
                    ("signpost.right.fill", "Trail markers")]
        case .gardens:
            return [("leaf.fill", "Botanical garden"), ("toilet.fill", "Restrooms"),
                    ("bag.fill", "Gift shop"), ("figure.2.arms.open", "Guided tours")]
        case .playgrounds:
            return [("figure.play", "Play structures"), ("car.fill", "Parking"),
                    ("umbrella.fill", "Shaded seating"), ("toilet.fill", "Restrooms")]
        case .waterfront:
            return [("water.waves", "Waterfront"), ("car.fill", "Parking"),
                    ("sailboat.fill", "Boating"), ("toilet.fill", "Restrooms")]
        case .sports:
            return [("sportscourt.fill", "Courts & fields"), ("car.fill", "Parking"),
                    ("drop.fill", "Water fountains"), ("toilet.fill", "Restrooms")]
        case .community:
            return [("building.2.fill", "Community space"), ("wifi", "Free Wi-Fi"),
                    ("cup.and.saucer.fill", "Café"), ("toilet.fill", "Restrooms")]
        }
    }

    /// Accessibility summary inferred from category.
    var accessibilityNote: String {
        switch category {
        case .trails, .scenic:
            return "Some unpaved terrain — partially wheelchair accessible."
        default:
            return "Wheelchair accessible with paved paths and accessible parking."
        }
    }
}
