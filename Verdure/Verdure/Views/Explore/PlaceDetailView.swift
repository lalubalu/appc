import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: Place
    @State private var showCelebration = false
    @State private var celebrationPoints = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(GameStateManager.self) private var gameState
    @Environment(PlacesAPIService.self) private var placesService
    @Environment(EventsAPIService.self) private var eventsService
    @Environment(LocationManager.self) private var locationManager

    private var isSaved: Bool { gameState.isPlaceSaved(place.id) }

    /// Real upcoming events matched to this place by venue name.
    private var eventsHere: [Event] {
        let name = place.name.lowercased()
        return eventsService.events
            .filter { $0.date > Date().addingTimeInterval(-3600) }
            .filter { $0.locationName.lowercased().contains(name) || name.contains($0.locationName.lowercased()) }
            .sorted { $0.date < $1.date }
    }

    /// Open Apple Maps with directions to the place (real coords when known).
    private func openDirections() {
        Haptics.tap()
        if let coord = place.coordinate {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
            item.name = place.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } else {
            let query = place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "http://maps.apple.com/?daddr=\(query)&dirflg=d") { openURL(url) }
        }
    }

    private var collectible: CollectiblePlace? {
        placesService.collectible(for: place)
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
                    ShareLink(item: "\(place.name) — found on Verdure. \(place.shortDescription)") {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                    }
                    .tint(Palette.ink)
                    .accessibilityLabel("Share \(place.name)")
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
                    if let urlString = place.photoURL, let url = URL(string: urlString) {
                        // Real photo from the place's source (NPS/RecGov/OSM).
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.45)],
                                                        startPoint: .center, endPoint: .bottom))
                        } placeholder: {
                            Image(systemName: place.imagePlaceholder)
                                .font(.system(size: 150, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.16))
                                .rotationEffect(.degrees(-8))
                                .offset(x: 70, y: 10)
                        }
                        .frame(height: 250)
                    } else {
                        Image(systemName: place.imagePlaceholder)
                            .font(.system(size: 150, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.16))
                            .rotationEffect(.degrees(-8))
                            .offset(x: 70, y: 10)
                            .clipped()
                    }
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
            if let rating = place.rating {   // only REAL ratings are shown
                statWell(String(format: "%.1f", rating), "\(place.reviewCount ?? 0) reviews", "star.fill", Palette.gold.base)
            }
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

            // Hours — real (OSM opening_hours) when available; otherwise typical
            // hours for this kind of place, labeled as such.
            HStack(spacing: 10) {
                Image(systemName: "clock.fill").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(kind.accent.base).frame(width: 22)
                Text(place.openHoursReal != nil ? "Hours" : "Typical hours")
                    .font(VType.body(13, .semibold)).foregroundStyle(Palette.inkSoft)
                Spacer()
                Text(place.openHoursReal ?? "\(place.openHours) · varies")
                    .font(VType.body(13, .semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            // Amenities
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Typical for \(place.category.rawValue.lowercased())").font(VType.body(13, .semibold)).foregroundStyle(Palette.inkSoft)
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
                           kind: .teal, fullWidth: true) { openDirections() }
                ClayButton(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark",
                           kind: .ghost, fullWidth: true) {
                    withAnimation(.spring(response: 0.3)) { gameState.togglePlaceSaved(place.id) }
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
                    celebrationPoints = gameState.collectPlace(c, userCoordinate: locationManager.userLocation?.coordinate)
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
            if eventsHere.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "calendar").foregroundStyle(Palette.inkFaint)
                    Text("No upcoming events at this location.")
                        .font(VType.body(14)).foregroundStyle(Palette.inkSoft)
                    Spacer()
                }
                .padding(Spacing.md)
                .background(ClayBackground(style: .inset, radius: Radius.md))
            } else {
                ForEach(eventsHere.prefix(3)) { event in
                    HStack(spacing: Spacing.md) {
                        ClayIconTile(systemImage: event.imagePlaceholder,
                                     kind: event.category.clayKind, size: 42, radius: Radius.chip)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(VType.display(14, .semibold)).foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text("\(event.date.formatted(date: .abbreviated, time: .omitted)) · \(event.time)")
                                .font(VType.body(12)).foregroundStyle(Palette.inkSoft).lineLimit(1)
                        }
                        Spacer()
                        PointsBadge(points: event.pointValue)
                    }
                    .padding(Spacing.sm)
                    .claySurface(.surface, radius: Radius.md, elevation: 0.7)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlaceDetailView(place: SampleData.places[0])
            .environment(GameStateManager())
            .environment(PlacesAPIService())
            .environment(EventsAPIService())
            .environment(LocationManager())
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
