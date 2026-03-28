import SwiftUI
import PhotosUI

struct EventsView: View {
    @Environment(GameStateManager.self) private var gameState
    @Environment(LocationManager.self) private var locationManager
    @Environment(EventsAPIService.self) private var eventsService
    @State private var selectedCategory: EventCategory? = nil
    @State private var selectedEvent: Event? = nil
    @State private var showCreateEvent = false

    private var filteredEvents: [Event] {
        guard let cat = selectedCategory else { return eventsService.events }
        return eventsService.events.filter { $0.category == cat }
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

                    // Loading indicator
                    if eventsService.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.connectifyGreen)
                            Text("Finding community events...")
                                .font(CFont.caption(13))
                                .foregroundStyle(.secondaryText)
                            Spacer()
                        }
                        .padding(.vertical, Spacing.md)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateEvent = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.connectifyGreen)
                    }
                }
            }
            .refreshable {
                await eventsService.refresh(around: locationManager.userCoordinate)
            }
            .task {
                await eventsService.fetchNearbyEvents(around: locationManager.userCoordinate)
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailSheet(event: event, dateFormatter: dateFormatter)
                    .environment(gameState)
                    .environment(locationManager)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showCreateEvent) {
                CreateEventSheet()
                    .environment(eventsService)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Points Banner

    private var pointsBanner: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(gameState.totalEventsAttended)")
                    .font(CFont.mono(36))
                    .foregroundStyle(.white)

                Text("events attended")
                    .font(CFont.caption(13))
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                    Text("\(gameState.pointsBalance) pts")
                        .font(CFont.headline(14))
                }
                .foregroundStyle(Color.connectifyGreenBright)
            }

            Spacer()

            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(Spacing.lg)
        .background(Color.connectifyGreenDeep)
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
            .padding(.vertical, 9)
            .background(selected ? Color.connectifyGreen : .cardSurface)
            .foregroundStyle(selected ? .white : .secondaryText)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create Event Sheet

private struct CreateEventSheet: View {
    @Environment(EventsAPIService.self) private var eventsService
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var organizer = ""
    @State private var locationName = ""
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endTime = Calendar.current.date(byAdding: .hour, value: 2, to: Date())!
    @State private var category: EventCategory = .meetup
    @State private var maxAttendees = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !organizer.trimmingCharacters(in: .whitespaces).isEmpty &&
        !locationName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: startTime)) – \(formatter.string(from: endTime))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    categoryPicker
                    formField(label: "EVENT TITLE", placeholder: "e.g. Spring Hackathon", text: $title)
                    descriptionField
                    formField(label: "ORGANIZED BY", placeholder: "e.g. Local Dev Collective", text: $organizer)
                    formField(label: "LOCATION", placeholder: "e.g. Downtown Library", text: $locationName)
                    dateTimeSection
                    maxAttendeesField
                    pointsInfo
                    errorAndSubmit
                }
                .padding(Spacing.md)
            }
            .background(.pageSurface)
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondaryText)
                }
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CATEGORY")
                .font(CFont.label(10))
                .tracking(0.8)
                .foregroundStyle(.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EventCategory.allCases) { cat in
                        categoryButton(for: cat)
                    }
                }
            }
        }
    }

    private func categoryButton(for cat: EventCategory) -> some View {
        let isSelected = category == cat
        return Button {
            category = cat
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.system(size: 11))
                Text(cat.rawValue)
                    .font(CFont.caption(12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.connectifyGreen : .cardSurface)
            .foregroundStyle(isSelected ? .white : .secondaryText)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DESCRIPTION")
                .font(CFont.label(10))
                .tracking(0.8)
                .foregroundStyle(.secondaryText)

            TextEditor(text: $description)
                .font(CFont.body(14))
                .frame(minHeight: 80)
                .padding(Spacing.sm)
                .background(.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(.subtleBorder, lineWidth: 0.5)
                }
        }
    }

    private var dateTimeSection: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DATE")
                    .font(CFont.label(10))
                    .tracking(0.8)
                    .foregroundStyle(.secondaryText)
                DatePicker("", selection: $date, in: Date()..., displayedComponents: .date)
                    .labelsHidden()
                    .tint(.connectifyGreen)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("START")
                    .font(CFont.label(10))
                    .tracking(0.8)
                    .foregroundStyle(.secondaryText)
                DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(.connectifyGreen)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("END")
                    .font(CFont.label(10))
                    .tracking(0.8)
                    .foregroundStyle(.secondaryText)
                DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(.connectifyGreen)
            }
        }
    }

    private var maxAttendeesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MAX ATTENDEES (OPTIONAL)")
                .font(CFont.label(10))
                .tracking(0.8)
                .foregroundStyle(.secondaryText)

            TextField("Leave empty for unlimited", text: $maxAttendees)
                .font(CFont.body(14))
                .keyboardType(.numberPad)
                .padding(Spacing.sm)
                .background(.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(.subtleBorder, lineWidth: 0.5)
                }
        }
    }

    private var pointsInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentAmber)
            Text("Attendees earn +\(category.defaultPoints) pts for checking in")
                .font(CFont.caption(13))
                .foregroundStyle(.secondaryText)
        }
        .padding(Spacing.sm)
        .background(Color.accentAmber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    @ViewBuilder
    private var errorAndSubmit: some View {
        if let error = errorMessage {
            Text(error)
                .font(CFont.caption(12))
                .foregroundStyle(.red)
        }

        Button {
            Task { await submit() }
        } label: {
            submitButtonLabel
        }
        .disabled(!isValid || isSubmitting)
        .buttonStyle(.plain)
    }

    private var submitButtonLabel: some View {
        HStack(spacing: 8) {
            if isSubmitting {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
            }
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14))
            Text("Create Event")
                .font(CFont.headline(16))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(isValid ? Color.connectifyGreen : Color.connectifyGreen.opacity(0.3))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func formField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(CFont.label(10))
                .tracking(0.8)
                .foregroundStyle(.secondaryText)

            TextField(placeholder, text: text)
                .font(CFont.body(14))
                .padding(Spacing.sm)
                .background(.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(.subtleBorder, lineWidth: 0.5)
                }
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil

        let maxAttendeesInt = Int(maxAttendees)

        let result = await eventsService.createEvent(
            title: title,
            description: description,
            organizer: organizer,
            date: date,
            time: timeString,
            locationName: locationName,
            maxAttendees: maxAttendeesInt,
            category: category
        )

        isSubmitting = false

        if result != nil {
            dismiss()
        } else {
            errorMessage = eventsService.lastError ?? "Failed to create event."
        }
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
        .background(
            HStack(spacing: 0) {
                Color.connectifyGreen.opacity(isCheckedIn ? 1 : 0.4)
                    .frame(width: 3)
                (isCheckedIn ? Color.greenCard : Color.cardSurface)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
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

                            // Description (if available)
                            if let desc = event.description, !desc.isEmpty {
                                Text(desc)
                                    .font(CFont.body(14))
                                    .foregroundStyle(.primaryText)
                                    .padding(Spacing.md)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.greenCard)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                            }

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
                            .background(.greenCard)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

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
        .environment(EventsAPIService())
}
