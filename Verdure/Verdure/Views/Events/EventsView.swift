import SwiftUI
import PhotosUI

struct EventsView: View {
    @Environment(GameStateManager.self) private var gameState
    @Environment(LocationManager.self) private var locationManager
    @Environment(EventsAPIService.self) private var eventsService
    @State private var selectedEvent: Event? = nil
    @State private var showCreateEvent = false
    @State private var selectedCategory: EventCategory? = nil
    @State private var searchText = ""
    @AppStorage("accountType") private var accountTypeRaw = AccountType.visitor.rawValue
    private var accountType: AccountType { AccountType(rawValue: accountTypeRaw) ?? .visitor }

    private var sourceEvents: [Event] {
        eventsService.events.isEmpty ? SampleData.events : eventsService.events
    }
    private var filteredEvents: [Event] {
        var result = sourceEvents
        if let cat = selectedCategory { result = result.filter { $0.category == cat } }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                $0.organizer.localizedCaseInsensitiveContains(q) ||
                $0.locationName.localizedCaseInsensitiveContains(q) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(q)
            }
        }
        return result
    }
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    kineticHero.dramaticRise(index: 0)
                    posterDeck.dramaticRise(index: 1)
                    upcomingTimeline.dramaticRise(index: 2)
                }
                .padding(.top, Spacing.sm)
                .padding(.bottom, 110)
            }
            .background(VerdureBackground())
            .refreshable { await eventsService.refresh(around: locationManager.userCoordinate) }
            .task { await eventsService.fetchNearbyEvents(around: locationManager.userCoordinate) }
            .sheet(item: $selectedEvent) { event in
                EventDetailSheet(event: event, dateFormatter: dateFormatter)
                    .environment(gameState).environment(locationManager)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showCreateEvent) {
                CreateEventSheet().environment(eventsService)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Kinetic hero (giant count-up + marquee)

    private var kineticHero: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    KickerLabel(text: "Happening near you", dot: Palette.gold.base)
                    Text("Events").font(VType.display(40, .bold)).foregroundStyle(Palette.ink)
                }
                Spacer()
                // Only organizers can create events.
                if accountType.canCreateEvents {
                    Button { Haptics.tap(); showCreateEvent = true } label: {
                        Image(systemName: "plus").font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Palette.spruce.onColor)
                            .frame(width: 48, height: 48)
                            .background(ClayBackground(style: .accent(.spruce), radius: Radius.chip, elevation: 0.6))
                    }
                    .buttonStyle(.plain)
                    .breathing(scale: 1.06, duration: 2.2)
                }
            }

            // Giant attended count with pulse halo
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                ZStack {
                    PulseHalo(color: Palette.teal.base.opacity(0.5), size: 120, lineWidth: 2)
                    CountUp(value: gameState.totalEventsAttended)
                        .font(VType.num(86, .bold)).monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(colors: [Palette.ink, Palette.spruce.base],
                                           startPoint: .top, endPoint: .bottom))
                        .breathing(scale: 1.03, duration: 3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("events").font(VType.display(20, .semibold)).foregroundStyle(Palette.inkSoft)
                    Text("attended").font(VType.display(20, .semibold)).foregroundStyle(Palette.inkSoft)
                    HStack(spacing: 5) {
                        Image(systemName: "leaf.circle.fill").font(.system(size: 12, weight: .bold))
                        Text("\(gameState.pointsBalance) pts").font(VType.num(13, .bold))
                    }
                    .foregroundStyle(Palette.gold.base).padding(.top, 4)
                }
                Spacer()
            }
            .padding(.leading, 6)

            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                TextField("Search events, hosts, places…", text: $searchText)
                    .font(VType.body(15)).foregroundStyle(Palette.ink)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint)
                    }
                }
            }
            .padding(.vertical, 13).padding(.horizontal, 16)
            .background(ClayBackground(style: .inset, radius: Radius.sm))

            // Tappable category filter row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    CategoryPill(label: "All", icon: "square.grid.2x2.fill",
                                 tint: Palette.spruce.base, isSelected: selectedCategory == nil) {
                        withAnimation(.spring(response: 0.35)) { selectedCategory = nil }
                    }
                    ForEach(EventCategory.allCases) { cat in
                        CategoryPill(label: cat.rawValue, icon: cat.icon, tint: cat.accent.base,
                                     isSelected: selectedCategory == cat) {
                            withAnimation(.spring(response: 0.35)) { selectedCategory = cat }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Poster deck (horizontal paging, scroll-driven tilt)

    private var posterDeck: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                KickerLabel(text: "Swipe the deck", color: Palette.teal.base)
                Spacer()
                Image(systemName: "hand.draw.fill").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, Spacing.md)

            if eventsService.isLoading && sourceEvents.isEmpty {
                loadingRow
            } else if filteredEvents.isEmpty {
                emptyDeck
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(filteredEvents) { event in
                            EventPoster(event: event, isCheckedIn: gameState.isCheckedIn(event.id))
                                .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 16)
                                .scrollTransition(.interactive) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                        .rotation3DEffect(.degrees(phase.value * 10),
                                                          axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                                        .opacity(phase.isIdentity ? 1 : 0.55)
                                }
                                .onTapGesture { Haptics.soft(); selectedEvent = event }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Spacing.md)
                }
                .scrollTargetBehavior(.viewAligned)
                .frame(height: 430)
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView().tint(Palette.teal.base)
            Text("Finding community events…").font(VType.body(13, .medium)).foregroundStyle(Palette.inkSoft)
            Spacer()
        }
        .frame(height: 430)
    }

    private var emptyDeck: some View {
        VStack(spacing: Spacing.md) {
            ClayIconTile(systemImage: "calendar.badge.exclamationmark", kind: .gold, size: 60, radius: Radius.md)
            Text("No events match")
                .font(VType.display(18, .semibold)).foregroundStyle(Palette.ink)
            Text(searchText.isEmpty ? "Try a different category." : "Try a different search or category.")
                .font(VType.body(13)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).frame(height: 300)
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Upcoming timeline (glowing vertical line)

    @ViewBuilder
    private var upcomingTimeline: some View {
        if !filteredEvents.isEmpty {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ClaySectionHeader(index: "↓", kicker: "On the calendar", title: "Upcoming",
                              accent: Palette.gold.base)
                .padding(.horizontal, Spacing.md)
            VStack(spacing: 0) {
                ForEach(Array(filteredEvents.prefix(5).enumerated()), id: \.element.id) { i, event in
                    TimelineRow(event: event, isCheckedIn: gameState.isCheckedIn(event.id),
                                isLast: i == min(5, filteredEvents.count) - 1)
                        .onTapGesture { Haptics.soft(); selectedEvent = event }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        }
    }
}

// MARK: - Event poster (full-bleed accent, oversized date)

private struct EventPoster: View {
    let event: Event
    let isCheckedIn: Bool
    private var kind: ClayStyle.ClayAccentKind { event.category.clayKind }
    private var on: Color { kind.accent.onColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: -6) {
                    Text(month).font(VType.display(18, .bold)).foregroundStyle(on.opacity(0.85))
                    Text(day).font(VType.num(72, .bold)).foregroundStyle(on)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: event.category.icon).font(.system(size: 11, weight: .bold))
                        Text(event.category.rawValue.uppercased()).font(VType.body(10, .bold)).tracking(0.6)
                    }
                    .foregroundStyle(on)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.chip))
                    if isCheckedIn {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 10, weight: .bold))
                            Text("ATTENDED").font(VType.body(9, .bold)).tracking(0.4)
                        }
                        .foregroundStyle(on)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.chip))
                    }
                }
            }

            Spacer()

            Text(event.title)
                .font(VType.display(30, .bold)).foregroundStyle(on)
                .lineLimit(2).minimumScaleFactor(0.7)
                .shadow(color: kind.accent.depth.opacity(0.4), radius: 4, x: 0, y: 2)
            Text(event.organizer).font(VType.body(14, .medium)).foregroundStyle(on.opacity(0.85))
                .padding(.top, 4)

            HStack(spacing: 12) {
                Label(event.time, systemImage: "clock.fill")
                Label(event.locationName, systemImage: "mappin")
            }
            .font(VType.body(12, .semibold)).foregroundStyle(on.opacity(0.85)).lineLimit(1).padding(.top, 10)

            HStack(spacing: 10) {
                HStack(spacing: -9) {
                    ForEach(0..<min(4, max(1, event.attendeeCount)), id: \.self) { _ in
                        Circle().fill(on.opacity(0.25))
                            .frame(width: 26, height: 26)
                            .overlay(Image(systemName: "person.fill").font(.system(size: 11)).foregroundStyle(on.opacity(0.8)))
                            .overlay(Circle().strokeBorder(on.opacity(0.4), lineWidth: 1.5))
                    }
                }
                Text(event.maxAttendees.map { "\(event.attendeeCount)/\($0)" } ?? "\(event.attendeeCount) going")
                    .font(VType.body(12, .semibold)).foregroundStyle(on.opacity(0.85))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "leaf.circle.fill").font(.system(size: 13, weight: .bold))
                    Text("+\(event.pointValue)").font(VType.num(16, .bold))
                }
                .foregroundStyle(on)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.chip))
            }
            .padding(.top, 16)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                kind.accent.faceGradient
                Image(systemName: event.imagePlaceholder)
                    .font(.system(size: 230, weight: .bold))
                    .foregroundStyle(on.opacity(0.10))
                    .rotationEffect(.degrees(-12)).offset(x: 90, y: 60)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: kind.accent.depth.opacity(0.5), radius: 26, x: 8, y: 16)
        .parallaxTilt(magnitude: 6, shadow: false)
    }

    private var day: String { let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: event.date) }
    private var month: String { let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: event.date).uppercased() }
}

// MARK: - Timeline row (glowing connector line)

private struct TimelineRow: View {
    let event: Event
    let isCheckedIn: Bool
    let isLast: Bool
    private var kind: ClayStyle.ClayAccentKind { event.category.clayKind }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(kind.accent.faceGradient).frame(width: 16, height: 16)
                        .shadow(color: kind.accent.base.opacity(0.6), radius: 5)
                    if isCheckedIn {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black))
                            .foregroundStyle(kind.accent.onColor)
                    }
                }
                if !isLast {
                    Rectangle()
                        .fill(LinearGradient(colors: [kind.accent.base.opacity(0.5), Palette.hairline],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 2.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(VType.display(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                HStack(spacing: 8) {
                    Text(dateStr).font(VType.num(11, .bold)).foregroundStyle(kind.accent.base)
                    Text(event.locationName).font(VType.body(11, .medium)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkFaint)
                .padding(.top, 2)
        }
        .padding(.bottom, isLast ? 0 : Spacing.md)
        .contentShape(Rectangle())
    }
    private var dateStr: String { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: event.date) }
}

// MARK: - Create event sheet

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
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return "\(f.string(from: startTime)) – \(f.string(from: endTime))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    categoryPicker
                    labeled("EVENT TITLE") { ClayField(placeholder: "e.g. Spring Hackathon", text: $title) }
                    labeled("DESCRIPTION") {
                        TextEditor(text: $description)
                            .font(VType.body(15)).foregroundStyle(Palette.ink).scrollContentBackground(.hidden)
                            .frame(minHeight: 90).padding(10)
                            .background(ClayBackground(style: .inset, radius: Radius.sm))
                    }
                    labeled("ORGANIZED BY") { ClayField(placeholder: "e.g. Local Dev Collective", text: $organizer) }
                    labeled("LOCATION") { ClayField(placeholder: "e.g. Downtown Library", text: $locationName) }
                    dateTimeSection
                    labeled("MAX ATTENDEES (OPTIONAL)") {
                        ClayField(placeholder: "Leave empty for unlimited", text: $maxAttendees, keyboard: .numberPad)
                    }
                    pointsInfo
                    if let error = errorMessage {
                        Text(error).font(VType.body(12, .medium)).foregroundStyle(Palette.danger)
                    }
                    ClayButton(isSubmitting ? "Creating…" : "Create Event", systemImage: "plus.circle.fill",
                               kind: .spruce, fullWidth: true) { Task { await submit() } }
                        .disabled(!isValid || isSubmitting).opacity(isValid ? 1 : 0.5)
                }
                .padding(Spacing.md)
            }
            .background(VerdureBackground())
            .navigationTitle("New Event").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.inkSoft)
                }
            }
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(VType.body(10, .bold)).tracking(0.8).foregroundStyle(Palette.inkSoft)
            content()
        }
    }

    private var categoryPicker: some View {
        labeled("CATEGORY") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(EventCategory.allCases) { cat in
                        CategoryPill(label: cat.rawValue, icon: cat.icon, tint: cat.accent.base,
                                     isSelected: category == cat) { category = cat }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            labeled("DATE") {
                DatePicker("", selection: $date, in: Date()..., displayedComponents: .date)
                    .labelsHidden().tint(Palette.spruce.base)
            }
            HStack(spacing: Spacing.lg) {
                labeled("START") {
                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden().tint(Palette.spruce.base)
                }
                labeled("END") {
                    DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                        .labelsHidden().tint(Palette.spruce.base)
                }
                Spacer()
            }
        }
    }

    private var pointsInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.circle.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.gold.base)
            Text("Attendees earn +\(category.defaultPoints) pts for checking in")
                .font(VType.body(13, .medium)).foregroundStyle(Palette.inkSoft)
        }
        .padding(Spacing.md).frame(maxWidth: .infinity, alignment: .leading)
        .background(ClayBackground(style: .inset, radius: Radius.sm))
    }

    private func submit() async {
        isSubmitting = true; errorMessage = nil
        let result = await eventsService.createEvent(
            title: title, description: description, organizer: organizer, date: date,
            time: timeString, locationName: locationName, maxAttendees: Int(maxAttendees), category: category)
        isSubmitting = false
        if result != nil { Haptics.success(); dismiss() }
        else { errorMessage = eventsService.lastError ?? "Failed to create event." }
    }
}

// MARK: - Event detail sheet

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

    private var isCheckedIn: Bool { gameState.isCheckedIn(event.id) }
    private var kind: ClayStyle.ClayAccentKind { event.category.clayKind }

    var body: some View {
        NavigationStack {
            ZStack {
                VerdureBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        hero
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text(event.title).font(VType.display(24, .semibold)).foregroundStyle(Palette.ink)
                            Text("Organized by \(event.organizer)").font(VType.body(14)).foregroundStyle(Palette.inkSoft)
                            if let desc = event.description, !desc.isEmpty {
                                Text(desc).font(VType.body(14)).foregroundStyle(Palette.ink).lineSpacing(3)
                                    .padding(Spacing.md).frame(maxWidth: .infinity, alignment: .leading)
                                    .claySurface(.surface, radius: Radius.md)
                            }
                            detailGrid
                            checkInSection
                            ClayButton("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                                       kind: .teal, fullWidth: true) {}
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                    .padding(.bottom, Spacing.xl)
                }
                .navigationBarTitleDisplayMode(.inline)

                if showCelebration { checkInCelebration.transition(.opacity) }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 0)
                .fill(kind.accent.faceGradient)
                .frame(height: 170)
                .overlay {
                    Image(systemName: event.imagePlaceholder).font(.system(size: 90, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.16)).rotationEffect(.degrees(-8)).offset(x: 90)
                }
                .clipped()
            HStack {
                Text(event.category.rawValue).font(VType.body(11, .bold))
                    .foregroundStyle(kind.accent.onColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.chip))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "leaf.circle.fill").font(.system(size: 11, weight: .bold))
                    Text("+\(event.pointValue) pts").font(VType.num(12, .bold))
                }
                .foregroundStyle(kind.accent.onColor)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.chip))
            }
            .padding(12)
        }
    }

    private var detailGrid: some View {
        VStack(spacing: Spacing.sm) {
            detailRow("calendar", "Date", dateFormatter.string(from: event.date))
            detailRow("clock.fill", "Time", event.time)
            detailRow("mappin.circle.fill", "Location", event.locationName)
            if let max = event.maxAttendees { detailRow("person.2.fill", "Capacity", "\(event.attendeeCount) / \(max)") }
            else { detailRow("person.2.fill", "Attending", "\(event.attendeeCount) people") }
            detailRow("leaf.circle.fill", "Points", "+\(event.pointValue) for attending")
        }
        .padding(Spacing.md)
        .claySurface(.surface, radius: Radius.md)
    }

    @ViewBuilder
    private var checkInSection: some View {
        if isCheckedIn {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.teal.base).font(.system(size: 18, weight: .bold))
                Text("Checked In").font(VType.body(16, .bold)).foregroundStyle(Palette.ink)
                Spacer()
                Text("\(event.pointValue) pts earned").font(VType.num(13, .bold)).foregroundStyle(Palette.teal.base)
            }
            .padding(Spacing.md).claySurface(.surface, radius: Radius.md)
        } else {
            VStack(spacing: Spacing.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Palette.gold.base)
                    Text("Be within 500 ft and upload proof of attendance to check in.")
                        .font(VType.body(12.5, .medium)).foregroundStyle(Palette.inkSoft)
                }
                .padding(Spacing.md).frame(maxWidth: .infinity, alignment: .leading)
                .background(ClayBackground(style: .inset, radius: Radius.sm))

                if proofPhotoData != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.teal.base)
                        Text("Proof photo attached").font(VType.body(13, .medium)).foregroundStyle(Palette.ink)
                        Spacer()
                        Button("Change") { showPhotoPicker = true }
                            .font(VType.body(12, .bold)).foregroundStyle(Palette.spruce.base)
                    }
                    .padding(Spacing.md).background(ClayBackground(style: .inset, radius: Radius.sm))

                    ClayButton("Check In  ·  +\(event.pointValue) pts", systemImage: "checkmark.circle.fill",
                               kind: .spruce, fullWidth: true) {
                        earnedPoints = gameState.checkInEvent(event)
                        if earnedPoints > 0 {
                            Haptics.success()
                            withAnimation(.spring(response: 0.4)) { showCelebration = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                                withAnimation { showCelebration = false }
                            }
                        }
                    }
                } else {
                    ClayButton("Upload Proof of Attendance", systemImage: "camera.viewfinder",
                               kind: .spruce, fullWidth: true) { showPhotoPicker = true }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) { proofPhotoData = data }
                }
            }
        }
    }

    private var checkInCelebration: some View {
        ZStack {
            Color(hex: 0x0A140F).opacity(0.78).ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                ClayIconTile(systemImage: "checkmark.circle.fill", kind: .teal, size: 96, radius: Radius.md)
                Text("CHECKED IN!").font(VType.display(28, .bold)).foregroundStyle(.white)
                HStack(spacing: 6) {
                    Image(systemName: "leaf.circle.fill").font(.system(size: 18, weight: .bold))
                    Text("+\(earnedPoints) pts").font(VType.num(24, .bold))
                }
                .foregroundStyle(Palette.gold.onColor)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(ClayBackground(style: .accent(.gold), radius: Radius.chip, elevation: 0.5))
                Text(event.title).font(VType.body(15)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .onTapGesture { withAnimation { showCelebration = false } }
    }

    private func detailRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.spruce.base).frame(width: 24)
            Text(label).font(VType.body(13, .medium)).foregroundStyle(Palette.inkSoft).frame(width: 72, alignment: .leading)
            Text(value).font(VType.body(14, .medium)).foregroundStyle(Palette.ink)
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
