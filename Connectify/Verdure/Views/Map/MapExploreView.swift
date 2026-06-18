import SwiftUI
import MapKit

struct MapExploreView: View {
    @Environment(GameStateManager.self) private var gameState
    @Environment(LocationManager.self) private var locationManager
    @Environment(PlacesAPIService.self) private var placesService
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedPlace: Place? = nil
    @State private var showList = false
    @State private var hasCentered = false
    @State private var hasFetched = false

    private var collectiblePlaces: [CollectiblePlace] {
        placesService.collectiblePlaces
    }

    private var nearbyUncollected: [CollectiblePlace] {
        gameState.uncollected(from: collectiblePlaces, nearbyOnly: true, userLocation: locationManager.userLocation)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    UserAnnotation()

                    if locationManager.userLocation != nil {
                        Annotation("", coordinate: locationManager.userCoordinate) {
                            RadarPulse()
                        }
                    }

                    ForEach(collectiblePlaces) { collectible in
                        Annotation(collectible.place.name, coordinate: collectible.coordinate) {
                            CollectibleMapPin(
                                collectible: collectible,
                                isSelected: selectedPlace?.id == collectible.place.id,
                                isCollected: gameState.isCollected(collectible.id),
                                isNearby: collectible.isNearby(from: locationManager.userLocation)
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35)) {
                                    selectedPlace = collectible.place
                                }
                            }
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                        .mapControlVisibility(.visible)
                }
                .onAppear {
                    centerOnUser()
                    fetchPlacesIfNeeded()
                }
                .onChange(of: locationManager.userLocation) { _, _ in
                    if !hasCentered { centerOnUser() }
                    fetchPlacesIfNeeded()
                }

                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.connectifyGreen)
                            Text("\(gameState.totalCollected)/\(collectiblePlaces.count)")
                                .font(CFont.label(12))
                                .foregroundStyle(.primaryText)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        if placesService.isLoading {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Loading...")
                                    .font(CFont.label(10))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial)
                            .foregroundStyle(.secondaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else if !locationManager.isAuthorized {
                            HStack(spacing: 4) {
                                Image(systemName: "location.slash.fill")
                                    .font(.system(size: 10))
                                Text("No GPS")
                                    .font(CFont.label(10))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial)
                            .foregroundStyle(Color.accentCoral)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Spacer()

                        VStack(spacing: 8) {
                            mapButton(icon: "location.fill") { centerOnUser() }
                            mapButton(icon: "list.bullet") { showList.toggle() }
                        }
                        .padding(.top, 48)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)

                    Spacer()

                    if !nearbyUncollected.isEmpty {
                        nearbyPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if let place = selectedPlace {
                        selectedPlaceCard(place)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.md)
                    }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showList) {
                mapListSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func fetchPlacesIfNeeded() {
        guard !hasFetched, locationManager.userLocation != nil else { return }
        hasFetched = true
        Task {
            await placesService.fetchNearbyPlaces(around: locationManager.userCoordinate)
        }
    }

    private func centerOnUser() {
        guard let loc = locationManager.userLocation else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            position = .region(MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
            ))
        }
        hasCentered = true
    }

    private var nearbyPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.connectifyGreen)
                Text("NEARBY — TAP TO EXPLORE")
                    .font(CFont.label(10))
                    .tracking(0.5)
                    .foregroundStyle(.secondaryText)
            }
            .padding(.horizontal, Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(nearbyUncollected) { collectible in
                        NearbyCollectibleChip(
                            collectible: collectible,
                            distance: locationManager.formattedDistance(to: collectible.coordinate)
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35)) {
                                selectedPlace = collectible.place
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.bottom, Spacing.xs)
        .background(.ultraThinMaterial)
    }

    private func selectedPlaceCard(_ place: Place) -> some View {
        let collectible = placesService.collectible(for: place)
        let collected = collectible.map { gameState.isCollected($0.id) } ?? false
        let distance = collectible.map { locationManager.formattedDistance(to: $0.coordinate) } ?? place.distance

        return NavigationLink(value: place) {
            HStack(spacing: Spacing.md) {
                PlacePlaceholder(icon: place.imagePlaceholder, color: place.accentColor, height: 70)
                    .frame(width: 70)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(place.category.rawValue)
                            .font(CFont.label(10))
                            .foregroundStyle(place.accentColor)
                            .textCase(.uppercase)
                        if let c = collectible {
                            RarityDot(rarity: c.rarity)
                        }
                        if collected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.connectifyGreen)
                        }
                    }

                    Text(place.name)
                        .font(CFont.headline(16))
                        .foregroundStyle(.primaryText)

                    HStack(spacing: Spacing.sm) {
                        Label(distance, systemImage: "location.fill")
                        if let c = collectible, !collected {
                            PointsBadge(points: c.pointValue)
                        }
                    }
                    .font(CFont.caption(11))
                    .foregroundStyle(.tertiaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiaryText)
            }
            .padding(Spacing.md)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .navigationDestination(for: Place.self) { place in
            PlaceDetailView(place: place)
        }
    }

    private func mapButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primaryText)
                .frame(width: 40, height: 40)
                .background(.regularMaterial)
                .clipShape(Circle())
        }
    }

    private var mapListSheet: some View {
        NavigationStack {
            List(collectiblePlaces) { collectible in
                let collected = gameState.isCollected(collectible.id)
                let dist = locationManager.formattedDistance(to: collectible.coordinate)
                HStack(spacing: Spacing.md) {
                    ZStack {
                        Image(systemName: collectible.place.category.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(collectible.place.accentColor)
                            .frame(width: 32)
                        if collected {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.connectifyGreen)
                                }
                                Spacer()
                            }
                            .frame(width: 32, height: 24)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(collectible.place.name)
                            .font(CFont.headline(15))
                            .foregroundStyle(.primaryText)
                        HStack(spacing: 6) {
                            Text(dist)
                                .font(CFont.caption(12))
                                .foregroundStyle(.secondaryText)
                            RarityBadge(rarity: collectible.rarity, size: .small)
                        }
                    }

                    Spacer()

                    if !collected {
                        PointsBadge(points: collectible.pointValue)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.connectifyGreen)
                    }
                }
                .listRowBackground(Color.cardSurface)
                .onTapGesture {
                    selectedPlace = collectible.place
                    showList = false
                }
            }
            .listStyle(.plain)
            .navigationTitle("All Places")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Collectible Map Pin

private struct CollectibleMapPin: View {
    let collectible: CollectiblePlace
    let isSelected: Bool
    let isCollected: Bool
    let isNearby: Bool

    @State private var pulseScale: CGFloat = 1.0

    private var isNearbyUncollected: Bool {
        !isCollected && isNearby
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if isNearbyUncollected {
                    Circle()
                        .fill(collectible.rarity.color.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - Double(pulseScale))
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                                pulseScale = 2.0
                            }
                        }
                }

                Circle()
                    .fill(pinFill)
                    .frame(width: pinSize, height: pinSize)
                    .shadow(color: shadowColor, radius: 4, y: 2)

                Image(systemName: collectible.place.category.icon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(iconColor)

                if isCollected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.connectifyGreen)
                                .background(Circle().fill(.white).frame(width: 10, height: 10))
                        }
                        Spacer()
                    }
                    .frame(width: pinSize, height: pinSize)
                }
            }
            .animation(.spring(response: 0.3), value: isSelected)

            Triangle()
                .fill(pinFill)
                .frame(width: 12, height: 6)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        }
    }

    private var pinSize: CGFloat { isSelected ? 44 : 36 }
    private var iconSize: CGFloat { isSelected ? 18 : 14 }

    private var pinFill: Color {
        if isSelected { return collectible.place.accentColor }
        if isCollected { return .white.opacity(0.7) }
        if isNearbyUncollected { return .white }
        return .white.opacity(0.6)
    }

    private var iconColor: Color {
        if isSelected { return .white }
        if isCollected { return collectible.place.accentColor.opacity(0.5) }
        return collectible.place.accentColor
    }

    private var shadowColor: Color {
        if isNearbyUncollected { return collectible.rarity.color.opacity(0.4) }
        return .black.opacity(0.2)
    }
}

// MARK: - Nearby Collectible Chip

private struct NearbyCollectibleChip: View {
    let collectible: CollectiblePlace
    let distance: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: collectible.rarity.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(collectible.rarity.color)

            VStack(alignment: .leading, spacing: 1) {
                Text(collectible.place.name)
                    .font(CFont.caption(12))
                    .foregroundStyle(.primaryText)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(distance)
                        .font(CFont.label(10))
                        .foregroundStyle(.secondaryText)
                    Text("·")
                        .foregroundStyle(.tertiaryText)
                    Text("+\(collectible.pointValue) pts")
                        .font(CFont.label(10))
                        .foregroundStyle(Color.accentAmber)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(collectible.rarity.color.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Radar Pulse

private struct RadarPulse: View {
    @State private var scale1: CGFloat = 0.5
    @State private var scale2: CGFloat = 0.5
    @State private var scale3: CGFloat = 0.5

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.connectifyGreen.opacity(0.08))
                .frame(width: 80, height: 80)
                .scaleEffect(scale1)
                .opacity(Double(2.0 - scale1) * 0.5)

            Circle()
                .fill(Color.connectifyGreen.opacity(0.12))
                .frame(width: 80, height: 80)
                .scaleEffect(scale2)
                .opacity(Double(2.0 - scale2) * 0.5)

            Circle()
                .fill(Color.connectifyGreen.opacity(0.15))
                .frame(width: 80, height: 80)
                .scaleEffect(scale3)
                .opacity(Double(2.0 - scale3) * 0.5)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false)) {
                scale1 = 2.0
            }
            withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(0.8)) {
                scale2 = 2.0
            }
            withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(1.6)) {
                scale3 = 2.0
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    MapExploreView()
        .environment(GameStateManager())
        .environment(LocationManager())
        .environment(PlacesAPIService())
}
