import SwiftUI

struct PlaceDetailView: View {
    let place: Place
    @State private var isSaved = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image
                ZStack(alignment: .bottomLeading) {
                    PlacePlaceholder(
                        icon: place.imagePlaceholder,
                        color: place.accentColor,
                        height: 280
                    )

                    // Gradient overlay
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 0))

                    VStack(alignment: .leading, spacing: 6) {
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
                        quickStat(value: place.isFeatured ? "Yes" : "—", label: "Featured", icon: "sparkles")
                    }
                    .padding(.vertical, Spacing.md)
                    .background(.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(.subtleBorder, lineWidth: 0.5)
                    }

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
                        ConnectifyButton(title: "Get Directions", icon: "arrow.triangle.turn.up.right.diamond.fill") {
                            // Placeholder: open Maps
                        }

                        HStack(spacing: Spacing.sm) {
                            ConnectifyButton(title: "Check In", icon: "checkmark.circle.fill", style: .secondary) {
                                // Placeholder
                            }

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
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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
    }

    private func quickStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.connectifyGreen)
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
    }
}
