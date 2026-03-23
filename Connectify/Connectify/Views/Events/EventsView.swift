import SwiftUI
import PhotosUI

struct EventsView: View {
    @Environment(GameStateManager.self) private var gameState
    @Environment(LocationManager.self) private var locationManager
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
                    // Points summary banner
                    pointsBanner

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
                            EventCard(event: event, isCheckedIn: gameState.isCheckedIn(event.id), dateFormatter: dateFormatter)
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
                    .environment(gameState)
                    .environment(locationManager)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Points Banner

    private var pointsBanner: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EARN POINTS BY ATTENDING")
                    .font(CFont.label(10))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 6) {
                    Text("\(gameState.totalEventsAttended)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("events attended")
                        .font(CFont.body(14))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Text("\(gameState.pointsBalance) pts available")
                    .font(CFont.caption(12))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "ticket.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(Spacing.lg)
        .background(
            LinearGradient(
                colors: [Color.connectifyGreen, Color.connectifyGreen.opacity(0.7), Color.accentMint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .padding(.horizontal, Spacing.md)
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
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(selected ? Color.connectifyGreen.opacity(0.4) : .subtleBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Card

private struct EventCard: View {
    let event: Event
    let isCheckedIn: Bool
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

                    if isCheckedIn {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("ATTENDED")
                                .font(CFont.label(8))
                                .tracking(0.3)
                        }
                        .foregroundStyle(Color.connectifyGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.connectifyGreen.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
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

                // Attendee bar + points
                HStack(spacing: 8) {
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

                    // Point value badge
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text(isCheckedIn ? "\(event.pointValue) pts" : "+\(event.pointValue) pts")
                            .font(CFont.label(11))
                    }
                    .foregroundStyle(isCheckedIn ? Color.connectifyGreen : Color.accentAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isCheckedIn ? Color.connectifyGreen.opacity(0.1) : Color.accentAmber.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .padding(Spacing.md)
        .background(.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(isCheckedIn ? Color.connectifyGreen.opacity(0.3) : .subtleBorder, lineWidth: isCheckedIn ? 1.5 : 0.5)
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
    @Environment(GameStateManager.self) private var gameState
    @Environment(LocationManager.self) private var locationManager
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var proofPhotoData: Data? = nil
    @State private var showCelebration = false
    @State private var earnedPoints = 0

    private var isCheckedIn: Bool {
        gameState.isCheckedIn(event.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
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
                                        .clipShape(RoundedRectangle(cornerRadius: 3))

                                    Spacer()

                                    // Points badge
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 11))
                                        Text("+\(event.pointValue) pts")
                                            .font(CFont.label(12))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
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
                                detailRow(icon: "star.fill", label: "Points", value: "+\(event.pointValue) for attending")
                            }
                            .padding(Spacing.md)
                            .background(.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .strokeBorder(.subtleBorder, lineWidth: 0.5)
                            }

                            // Check-in section
                            checkInSection

                            ConnectifyButton(title: "Get Directions", icon: "arrow.triangle.turn.up.right.diamond.fill", style: .secondary) {
                                // Placeholder
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                }
                .background(.pageSurface)
                .navigationBarTitleDisplayMode(.inline)

                // Celebration overlay
                if showCelebration {
                    checkInCelebration
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Check-in Section

    @ViewBuilder
    private var checkInSection: some View {
        if isCheckedIn {
            // Already checked in
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.connectifyGreen)
                Text("Checked In")
                    .font(CFont.headline(16))
                    .foregroundStyle(.primaryText)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                    Text("\(event.pointValue) pts earned")
                        .font(CFont.label(12))
                }
                .foregroundStyle(Color.connectifyGreen)
            }
            .padding(Spacing.md)
            .background(.greenSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.connectifyGreen.opacity(0.3), lineWidth: 1)
            }
        } else {
            // Check-in flow
            VStack(spacing: Spacing.sm) {
                // Info banner
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accentAmber)
                    Text("You must be within 500 ft and upload proof of attendance to check in.")
                        .font(CFont.caption(12))
                        .foregroundStyle(.secondaryText)
                }
                .padding(Spacing.sm)
                .background(Color.accentAmber.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                if proofPhotoData != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.connectifyGreen)
                        Text("Proof photo attached")
                            .font(CFont.caption(13))
                            .foregroundStyle(.primaryText)
                        Spacer()
                        Button("Change") { showPhotoPicker = true }
                            .font(CFont.label(12))
                            .foregroundStyle(Color.connectifyGreen)
                    }
                    .padding(Spacing.sm)
                    .background(.greenSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                    ConnectifyButton(
                        title: "Check In — +\(event.pointValue) pts",
                        icon: "checkmark.circle.fill"
                    ) {
                        earnedPoints = gameState.checkInEvent(event)
                        if earnedPoints > 0 {
                            withAnimation(.spring(response: 0.4)) {
                                showCelebration = true
                            }
                            // Auto-dismiss celebration
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation { showCelebration = false }
                            }
                        }
                    }
                } else {
                    ConnectifyButton(
                        title: "Upload Proof of Attendance",
                        icon: "camera.viewfinder"
                    ) {
                        showPhotoPicker = true
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        proofPhotoData = data
                    }
                }
            }
        }
    }

    // MARK: - Check-in Celebration

    private var checkInCelebration: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.connectifyGreen)

                Text("CHECKED IN!")
                    .font(CFont.display(28))
                    .foregroundStyle(.white)

                Text("+\(earnedPoints) pts")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentAmber)

                Text(event.title)
                    .font(CFont.body(16))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .onTapGesture {
            withAnimation { showCelebration = false }
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
        .environment(GameStateManager())
        .environment(LocationManager())
}
