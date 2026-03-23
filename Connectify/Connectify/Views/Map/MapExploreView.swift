import SwiftUI
import MapKit

struct MapExploreView: View {
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650),
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        )
    )
    @State private var selectedPlace: Place? = nil
    @State private var showList = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    ForEach(SampleData.places) { place in
                        Annotation(place.name, coordinate: coordinateFor(place)) {
                            PlaceMapPin(place: place, isSelected: selectedPlace?.id == place.id)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.35)) {
                                        selectedPlace = place
                                    }
                                }
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))

                VStack(spacing: 0) {
                    // Top controls
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            mapButton(icon: "location.fill") {
                                // Placeholder: center on user
                            }
                            mapButton(icon: "list.bullet") {
                                showList.toggle()
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)

                    Spacer()

                    // Selected place card
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

    // MARK: - Selected Place Card

    private func selectedPlaceCard(_ place: Place) -> some View {
        NavigationLink(value: place) {
            HStack(spacing: Spacing.md) {
                PlacePlaceholder(icon: place.imagePlaceholder, color: place.accentColor, height: 70)
                    .frame(width: 70)

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.category.rawValue)
                        .font(CFont.label(10))
                        .foregroundStyle(place.accentColor)
                        .textCase(.uppercase)

                    Text(place.name)
                        .font(CFont.headline(16))
                        .foregroundStyle(.primaryText)

                    HStack(spacing: Spacing.sm) {
                        Label(place.distance, systemImage: "location.fill")
                        Label(String(format: "%.1f", place.rating), systemImage: "star.fill")
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

    // MARK: - Map Button

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

    // MARK: - Map List Sheet

    private var mapListSheet: some View {
        NavigationStack {
            List(SampleData.places) { place in
                HStack(spacing: Spacing.md) {
                    Image(systemName: place.category.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(place.accentColor)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(CFont.headline(15))
                            .foregroundStyle(.primaryText)
                        Text("\(place.category.rawValue) · \(place.distance)")
                            .font(CFont.caption(12))
                            .foregroundStyle(.secondaryText)
                    }

                    Spacer()

                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentAmber)
                        Text(String(format: "%.1f", place.rating))
                            .font(CFont.caption(12))
                            .foregroundStyle(.secondaryText)
                    }
                }
                .listRowBackground(Color.cardSurface)
                .onTapGesture {
                    selectedPlace = place
                    showList = false
                }
            }
            .listStyle(.plain)
            .navigationTitle("All Places")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Coordinate Generator (placeholder)
    // Generates deterministic offsets for demo pins around center

    private func coordinateFor(_ place: Place) -> CLLocationCoordinate2D {
        let hash = abs(place.name.hashValue)
        let latOffset = Double(hash % 1000) / 20000.0 - 0.025
        let lngOffset = Double((hash / 1000) % 1000) / 20000.0 - 0.025
        return CLLocationCoordinate2D(
            latitude: 44.9778 + latOffset,
            longitude: -93.2650 + lngOffset
        )
    }
}

// MARK: - Map Pin

private struct PlaceMapPin: View {
    let place: Place
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? place.accentColor : .white)
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                Image(systemName: place.category.icon)
                    .font(.system(size: isSelected ? 18 : 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : place.accentColor)
            }
            .animation(.spring(response: 0.3), value: isSelected)

            // Pin tail
            Triangle()
                .fill(isSelected ? place.accentColor : .white)
                .frame(width: 12, height: 6)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
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
}
