import SwiftUI

struct EventsView: View {
    @State private var selectedCategory: EventCategory? = nil
    @State private var selectedEvent: Event? = nil

    private var filteredEvents: [Event] {
        guard let cat = selectedCategory else { return SampleData.events }
        return SampleData.events.filter { $0.category == cat }
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Category filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(label: "All", icon: "calendar", selected: selectedCategory == nil) {
                                withAnimation(.spring(response: 0.3)) { selectedCategory = nil }
                            }
                            ForEach(EventCategory.allCases) { cat in
                                filterChip(label: cat.rawValue, icon: cat.icon, selected: selectedCategory == cat) {
                                    withAnimation(.spring(response: 0.3)) { selectedCategory = cat }
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }

                    // Events list
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEvents) { event in
                            EventCard(event: event, dateFormatter: dateFormatter)
                                .onTapGesture { selectedEvent = event }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(.pageSurface)
            .navigationTitle("Events")
            .sheet(item: $selectedEvent) { event in
                EventDetailSheet(event: event, dateFormatter: dateFormatter)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func filterChip(label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(CFont.caption(13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Color.connectifyGreen.opacity(0.15) : .cardSurface)
            .foregroundStyle(selected ? Color.connectifyGreen : .secondaryText)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(selected ? Color.connectifyGreen.opacity(0.4) : .subtleBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Card

private struct EventCard: View {
    let event: Event
    let dateFormatter: DateFormatter

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Date column
            VStack(spacing: 2) {
                Text(dayOfWeek(event.date))
                    .font(CFont.label(10))
                    .foregroundStyle(.secondaryText)
                    .textCase(.uppercase)

                Text(dayNumber(event.date))
                    .font(CFont.title(24))
                    .foregroundStyle(.primaryText)

                Text(monthShort(event.date))
                    .font(CFont.label(10))
                    .foregroundStyle(.secondaryText)
                    .textCase(.uppercase)
            }
            .frame(width: 48)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: event.category.icon)
                        .font(.system(size: 10))
                    Text(event.category.rawValue.uppercased())
                        .font(CFont.label(10))
                        .tracking(0.5)
                }
                .foregroundStyle(Color.connectifyGreen)

                Text(event.title)
                    .font(CFont.headline(16))
                    .foregroundStyle(.primaryText)

                Text(event.organizer)
                    .font(CFont.caption(13))
                    .foregroundStyle(.secondaryText)

                HStack(spacing: Spacing.md) {
                    Label(event.time, systemImage: "clock.fill")
                    Label(event.locationName, systemImage: "mappin")
                }
                .font(CFont.caption(11))
                .foregroundStyle(.tertiaryText)
                .lineLimit(1)

                // Attendee bar
                HStack(spacing: 8) {
                    // Stacked avatars placeholder
                    HStack(spacing: -8) {
                        ForEach(0..<min(3, event.attendeeCount), id: \.self) { _ in
                            Circle()
                                .fill(Color.connectifyGreen.opacity(0.3))
                                .frame(width: 20, height: 20)
                                .overlay {
                                    Circle().strokeBorder(.cardSurface, lineWidth: 1.5)
                                }
                        }
                    }

                    if let max = event.maxAttendees {
                        Text("\(event.attendeeCount)/\(max) going")
                            .font(CFont.caption(11))
                            .foregroundStyle(.secondaryText)
                    } else {
                        Text("\(event.attendeeCount) going")
                            .font(CFont.caption(11))
                            .foregroundStyle(.secondaryText)
                    }

                    Spacer()

                    XPBadge(xp: 50)
                }
            }
        }
        .padding(Spacing.md)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(.subtleBorder, lineWidth: 0.5)
        }
    }

    private func dayOfWeek(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date)
    }
    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }
    private func monthShort(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: date)
    }
}

// MARK: - Event Detail Sheet

private struct EventDetailSheet: View {
    let event: Event
    let dateFormatter: DateFormatter

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Header image placeholder
                    ZStack {
                        PlacePlaceholder(
                            icon: event.imagePlaceholder,
                            color: Color.connectifyGreen,
                            height: 160
                        )

                        VStack {
                            Spacer()
                            HStack {
                                Text(event.category.rawValue)
                                    .font(CFont.label(11))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            .padding(12)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(event.title)
                            .font(CFont.title(22))
                            .foregroundStyle(.primaryText)

                        Text("Organized by \(event.organizer)")
                            .font(CFont.body(14))
                            .foregroundStyle(.secondaryText)

                        // Details grid
                        VStack(spacing: Spacing.sm) {
                            detailRow(icon: "calendar", label: "Date", value: dateFormatter.string(from: event.date))
                            detailRow(icon: "clock.fill", label: "Time", value: event.time)
                            detailRow(icon: "mappin.circle.fill", label: "Location", value: event.locationName)
                            if let max = event.maxAttendees {
                                detailRow(icon: "person.2.fill", label: "Capacity", value: "\(event.attendeeCount) / \(max)")
                            } else {
                                detailRow(icon: "person.2.fill", label: "Attending", value: "\(event.attendeeCount) people")
                            }
                        }
                        .padding(Spacing.md)
                        .background(.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(.subtleBorder, lineWidth: 0.5)
                        }

                        ConnectifyButton(title: "RSVP — I'm Going", icon: "hand.raised.fill") {
                            // Placeholder
                        }

                        ConnectifyButton(title: "Get Directions", icon: "arrow.triangle.turn.up.right.diamond.fill", style: .secondary) {
                            // Placeholder
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
            .background(.pageSurface)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.connectifyGreen)
                .frame(width: 24)

            Text(label)
                .font(CFont.caption(13))
                .foregroundStyle(.secondaryText)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(CFont.body(14))
                .foregroundStyle(.primaryText)

            Spacer()
        }
    }
}

#Preview {
    EventsView()
}
