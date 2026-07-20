import SwiftUI
import PhotosUI

struct EventsView: View {
    @Environment(GameStateManager.self) private var gameState
    @Environment(LocationManager.self) private var locationManager
    @Environment(EventsAPIService.self) private var eventsService
    @State private var selectedEvent: Event? = nil
    @State private var showCreateEvent = false
    @State private var showSaved = false
    @State private var showCalendar = false
    @State private var showInterestPicker = false
    @State private var selectedCategory: EventCategory? = nil
    @State private var searchText = ""
    @AppStorage("accountType") private var accountTypeRaw = AccountType.visitor.rawValue
    @AppStorage("interestCategories") private var interestCategoriesRaw = ""
    private var accountType: AccountType { AccountType(rawValue: accountTypeRaw) ?? .visitor }

    private var sourceEvents: [Event] {
        eventsService.events.isEmpty ? SampleData.events : eventsService.events
    }

    // MARK: Personalization ("For You")

    /// The user's chosen interests (set in onboarding, editable here).
    private var interests: Set<PlaceCategory> {
        Set(interestCategoriesRaw.split(separator: ",").compactMap { PlaceCategory(rawValue: String($0)) })
    }
    /// Event categories those interests map to (see PlaceCategory.relatedEventCategories).
    private var preferredEventCategories: Set<EventCategory> {
        Set(interests.flatMap(\.relatedEventCategories))
    }
    /// Upcoming events matching the user's interests — soonest first, not yet attended.
    private var forYouEvents: [Event] {
        guard !preferredEventCategories.isEmpty else { return [] }
        let cutoff = Date().addingTimeInterval(-3600)
        return sourceEvents
            .filter { $0.date > cutoff && preferredEventCategories.contains($0.category) && !gameState.isCheckedIn($0.id) }
            .sorted { $0.date < $1.date }
            .prefix(6)
            .map { $0 }
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
    private var hasActiveSearch: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Events shown in the deck/timeline. A category filter never blanks the screen —
    /// it falls back to all events; only an explicit text search can yield a true "no match".
    private var displayEvents: [Event] {
        (filteredEvents.isEmpty && !hasActiveSearch) ? sourceEvents : filteredEvents
    }
    /// True when the selected category had no events and we fell back to showing all.
    private var categoryFellBack: Bool {
        selectedCategory != nil && filteredEvents.isEmpty && !hasActiveSearch
    }
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    kineticHero.dramaticRise(index: 0)
                    forYouSection.dramaticRise(index: 1)
                    posterDeck.dramaticRise(index: 2)
                    upcomingTimeline.dramaticRise(index: 3)
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
            .sheet(isPresented: $showSaved) {
                SavedEventsView(allEvents: sourceEvents, dateFormatter: dateFormatter)
                    .environment(gameState).environment(locationManager)
            }
            .sheet(isPresented: $showCalendar) {
                EventCalendarView(allEvents: sourceEvents, dateFormatter: dateFormatter)
                    .environment(gameState).environment(locationManager)
            }
            .sheet(isPresented: $showInterestPicker) {
                InterestPickerSheet()
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - For You (personalized recommendations)

    @ViewBuilder
    private var forYouSection: some View {
        if interests.isEmpty {
            // No interests picked yet → invite personalization.
            Button { Haptics.tap(); showInterestPicker = true } label: {
                HStack(spacing: Spacing.md) {
                    ClayIconTile(systemImage: "sparkles", kind: .gold, size: 46, radius: Radius.chip)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Get event picks for you")
                            .font(VType.display(16, .semibold)).foregroundStyle(Palette.ink)
                        Text("Tell us what you love and we'll surface matching events.")
                            .font(VType.body(12.5)).foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.spruce.base)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .claySurface(.surface, radius: Radius.lg, elevation: 1.0)
            }
            .buttonStyle(Card3DButtonStyle())
            .padding(.horizontal, Spacing.md)
            .accessibilityLabel("Get event picks for you")
            .accessibilityHint("Opens interest selection to personalize event recommendations.")
        } else if !forYouEvents.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: 6) {
                    KickerLabel(text: "For you", color: Palette.gold.base, dot: Palette.gold.base)
                    Spacer()
                    Button { Haptics.tap(); showInterestPicker = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .bold))
                            Text("Tune").font(VType.body(12, .bold))
                        }
                        .foregroundStyle(Palette.spruce.base)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(ClayBackground(style: .surface, radius: Radius.chip, elevation: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tune recommendations")
                    .accessibilityHint("Edit the interests used for your event picks.")
                }
                .padding(.horizontal, Spacing.md)

                Text("Picked from your interests")
                    .font(VType.body(12, .medium)).foregroundStyle(Palette.inkFaint)
                    .padding(.horizontal, Spacing.md)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(forYouEvents) { event in
                            ForYouEventCard(event: event, dateFormatter: dateFormatter)
                                .onTapGesture { Haptics.soft(); selectedEvent = event }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 4)
                }
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
                HStack(spacing: 10) {
                    // Calendar view
                    Button { Haptics.tap(); showCalendar = true } label: {
                        Image(systemName: "calendar").font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Palette.teal.base)
                            .frame(width: 48, height: 48)
                            .background(ClayBackground(style: .surface, radius: Radius.chip, elevation: 0.6))
                    }
                    .buttonStyle(.plain)

                    // Saved / bookmarked events
                    Button { Haptics.tap(); showSaved = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bookmark.fill").font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Palette.gold.base)
                                .frame(width: 48, height: 48)
                                .background(ClayBackground(style: .surface, radius: Radius.chip, elevation: 0.6))
                            if !gameState.savedEventIDs.isEmpty {
                                Text("\(gameState.savedEventIDs.count)")
                                    .font(VType.num(10, .bold)).foregroundStyle(Palette.gold.onColor)
                                    .padding(4).background(Circle().fill(Palette.gold.base))
                                    .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .buttonStyle(.plain)

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
            }

            // Attended summary — card layout (per feedback)
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    CountUp(value: gameState.totalEventsAttended)
                        .font(VType.num(54, .bold)).monospacedDigit()
                        .foregroundStyle(Palette.evergreen.onColor)
                        .breathing(scale: 1.03, duration: 3)
                    Text("events attended").font(VType.body(14, .semibold))
                        .foregroundStyle(Palette.evergreen.onColor.opacity(0.85))
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill").font(.system(size: 12, weight: .bold))
                        Text("\(gameState.pointsBalance) pts").font(VType.num(14, .bold))
                    }
                    .foregroundStyle(Palette.gold.base).padding(.top, 4)
                }
                Spacer()
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Palette.evergreen.onColor.opacity(0.55))
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(ClayBackground(style: .accent(.evergreen), radius: Radius.lg, elevation: 1.1))

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
            HStack(spacing: 6) {
                KickerLabel(text: "Featured events", color: Palette.teal.base)
                Spacer()
                Image(systemName: "bookmark").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
                Text("tap to save").font(VType.body(11, .medium)).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, Spacing.md)

            if categoryFellBack {
                Text("No \(selectedCategory?.rawValue ?? "") events right now — showing all.")
                    .font(VType.body(12, .medium)).foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, Spacing.md)
            }

            if eventsService.isLoading && sourceEvents.isEmpty {
                loadingRow
            } else if displayEvents.isEmpty {
                emptyDeck
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(displayEvents) { event in
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
        if !displayEvents.isEmpty {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ClaySectionHeader(index: "↓", kicker: "On the calendar", title: "Upcoming",
                              accent: Palette.gold.base)
                .padding(.horizontal, Spacing.md)
            VStack(spacing: 0) {
                ForEach(Array(displayEvents.prefix(5).enumerated()), id: \.element.id) { i, event in
                    TimelineRow(event: event, isCheckedIn: gameState.isCheckedIn(event.id),
                                isLast: i == min(5, displayEvents.count) - 1)
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
    @Environment(GameStateManager.self) private var gameState
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
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { gameState.toggleSaved(event) }
                    } label: {
                        Image(systemName: gameState.isSaved(event.id) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(on)
                            .symbolEffect(.bounce, value: gameState.isSaved(event.id))
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
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
    @Environment(\.openURL) private var openURL
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var proofPhotoData: Data? = nil
    @State private var showCelebration = false
    @State private var earnedPoints = 0

    private var isCheckedIn: Bool { gameState.isCheckedIn(event.id) }
    private var kind: ClayStyle.ClayAccentKind { event.category.clayKind }

    /// Open Apple Maps in turn-by-turn directions mode, routing from the user's
    /// current location to the event address (daddr = destination, not a search).
    private func openDirections() {
        Haptics.tap()
        let dest = event.locationName
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?daddr=\(dest)&dirflg=d") { openURL(url) }
    }

    /// Open the event's website if it has one, else a web search for more info.
    private func openMoreInfo() {
        Haptics.tap()
        if let site = event.website, let url = URL(string: site.hasPrefix("http") ? site : "https://\(site)") {
            openURL(url); return
        }
        let q = "\(event.title) \(event.organizer) \(event.locationName)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(q)") { openURL(url) }
    }

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
                                       kind: .teal, fullWidth: true) { openDirections() }
                            ClayButton(event.website != nil ? "Visit Website" : "More Info",
                                       systemImage: "safari.fill", kind: .ghost, fullWidth: true) { openMoreInfo() }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                    .padding(.bottom, Spacing.xl)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                gameState.toggleSaved(event)
                            }
                        } label: {
                            Image(systemName: gameState.isSaved(event.id) ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(gameState.isSaved(event.id) ? Palette.gold.base : Palette.inkSoft)
                                .symbolEffect(.bounce, value: gameState.isSaved(event.id))
                        }
                    }
                }

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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Checked in. \(event.pointValue) points earned.")
        } else {
            VStack(spacing: Spacing.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Palette.gold.base)
                    Text("Be within 500 ft and upload proof of attendance to check in.")
                        .font(VType.body(12.5, .medium)).foregroundStyle(Palette.inkSoft)
                }
                .padding(Spacing.md).frame(maxWidth: .infinity, alignment: .leading)
                .background(ClayBackground(style: .inset, radius: Radius.sm))
                .accessibilityElement(children: .combine)

                if proofPhotoData != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.teal.base)
                        Text("Proof photo attached").font(VType.body(13, .medium)).foregroundStyle(Palette.ink)
                        Spacer()
                        Button("Change") { showPhotoPicker = true }
                            .font(VType.body(12, .bold)).foregroundStyle(Palette.spruce.base)
                            .accessibilityLabel("Change proof photo")
                    }
                    .padding(Spacing.md).background(ClayBackground(style: .inset, radius: Radius.sm))

                    ClayButton("Check In  ·  +\(event.pointValue) pts", systemImage: "checkmark.circle.fill",
                               kind: .spruce, fullWidth: true) {
                        earnedPoints = gameState.checkInEvent(event)
                        if earnedPoints > 0 {
                            Haptics.success()
                            AccessibilityNotification.Announcement(
                                "Checked in to \(event.title). Earned \(earnedPoints) points."
                            ).post()
                            withAnimation(.spring(response: 0.4)) { showCelebration = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                                withAnimation { showCelebration = false }
                            }
                        }
                    }
                    .accessibilityLabel("Check in to \(event.title)")
                    .accessibilityHint("Earns \(event.pointValue) points. Requires being at the event.")
                } else {
                    ClayButton("Upload Proof of Attendance", systemImage: "camera.viewfinder",
                               kind: .spruce, fullWidth: true) { showPhotoPicker = true }
                        .accessibilityHint("Opens your photo library to attach a photo taken at the event.")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checked in to \(event.title). Earned \(earnedPoints) points.")
        .accessibilityHint("Double tap to dismiss.")
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

// MARK: - For You event card (compact clay poster)

private struct ForYouEventCard: View {
    let event: Event
    let dateFormatter: DateFormatter
    private var kind: ClayStyle.ClayAccentKind { event.category.clayKind }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ClayIconTile(systemImage: event.imagePlaceholder, kind: kind, size: 44, radius: Radius.chip)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "leaf.circle.fill").font(.system(size: 10, weight: .bold))
                    Text("+\(event.pointValue)").font(VType.num(11, .bold))
                }
                .foregroundStyle(Palette.gold.base)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(ClayBackground(style: .inset, radius: Radius.chip))
            }
            Text(event.title)
                .font(VType.display(15, .semibold)).foregroundStyle(Palette.ink)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Label(dateFormatter.string(from: event.date), systemImage: "calendar")
                Label(event.locationName, systemImage: "mappin.circle.fill").lineLimit(1)
            }
            .font(VType.num(11, .semibold)).foregroundStyle(Palette.inkSoft)
            HStack(spacing: 5) {
                Circle().fill(kind.accent.base).frame(width: 6, height: 6)
                Text(event.category.rawValue).font(VType.body(10, .bold))
                    .foregroundStyle(kind.accent.base)
            }
        }
        .padding(Spacing.md)
        .frame(width: 210, height: 190, alignment: .topLeading)
        .claySurface(.surface, radius: Radius.md, elevation: 0.9)
        .overlay(alignment: .top) {
            Capsule().fill(kind.accent.faceGradient).frame(height: 5)
                .padding(.horizontal, 22).offset(y: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.category.rawValue), \(dateFormatter.string(from: event.date)) at \(event.locationName), earns \(event.pointValue) points")
        .accessibilityHint("Opens event details.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Interest picker (personalizes the For You section)

private struct InterestPickerSheet: View {
    @AppStorage("interestCategories") private var interestCategoriesRaw = ""
    @Environment(\.dismiss) private var dismiss

    private var selected: Set<PlaceCategory> {
        Set(interestCategoriesRaw.split(separator: ",").compactMap { PlaceCategory(rawValue: String($0)) })
    }

    private func toggle(_ category: PlaceCategory) {
        var current = selected
        if current.contains(category) { current.remove(category) } else { current.insert(category) }
        interestCategoriesRaw = current.map(\.rawValue).joined(separator: ",")
        Haptics.tap()
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Pick what draws you outdoors — your event recommendations follow.")
                        .font(VType.body(14)).foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, Spacing.md)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(PlaceCategory.allCases) { category in
                            let isSelected = selected.contains(category)
                            Button { toggle(category) } label: {
                                VStack(spacing: 10) {
                                    ClayIconTile(systemImage: category.icon, kind: category.clayKind,
                                                 size: 44, radius: Radius.chip)
                                    Text(category.rawValue)
                                        .font(VType.body(13, .semibold))
                                        .foregroundStyle(isSelected ? category.accent.onColor : Palette.ink)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(ClayPressButtonStyle(
                                style: isSelected ? .accent(category.clayKind) : .surface,
                                radius: Radius.md, elevation: 0.7))
                            .accessibilityLabel(category.rawValue)
                            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                            .accessibilityHint(isSelected ? "Double tap to remove from your interests." : "Double tap to add to your interests.")
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xl)
            }
            .background(VerdureBackground())
            .navigationTitle("Your Interests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(VType.body(15, .semibold)).foregroundStyle(Palette.spruce.base)
                }
            }
        }
    }
}

#Preview {
    EventsView()
        .environment(GameStateManager())
        .environment(LocationManager())
        .environment(EventsAPIService())
}

// MARK: - Saved / bookmarked events

private struct SavedEventsView: View {
    let allEvents: [Event]
    let dateFormatter: DateFormatter
    @Environment(GameStateManager.self) private var gameState
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEvent: Event?

    private var savedEvents: [Event] {
        allEvents.filter { gameState.isSaved($0.id) }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                if savedEvents.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(savedEvents.enumerated()), id: \.element.id) { i, event in
                            TimelineRow(event: event, isCheckedIn: gameState.isCheckedIn(event.id),
                                        isLast: i == savedEvents.count - 1)
                                .onTapGesture { Haptics.soft(); selectedEvent = event }
                        }
                    }
                    .padding(Spacing.md)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .background(VerdureBackground())
            .navigationTitle("Saved Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event, dateFormatter: dateFormatter)
                .environment(gameState).environment(locationManager)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            ClayIconTile(systemImage: "bookmark.slash", kind: .gold, size: 66, radius: Radius.md)
            Text("No saved events yet").font(VType.display(19, .semibold)).foregroundStyle(Palette.ink)
            Text("Tap the bookmark on any event to save it here for later.")
                .font(VType.body(14)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 80).padding(.horizontal, Spacing.xl)
    }
}

// MARK: - Events calendar (month grid with event dots)

private struct EventCalendarView: View {
    let allEvents: [Event]
    let dateFormatter: DateFormatter
    @Environment(GameStateManager.self) private var gameState
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss
    @State private var monthAnchor = Date()
    @State private var selectedDay: Date?
    @State private var selectedEvent: Event?

    private let cal = Calendar.current
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    private var eventsByDay: [Date: [Event]] {
        Dictionary(grouping: allEvents) { cal.startOfDay(for: $0.date) }
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: monthAnchor)
    }

    /// Calendar cells for the anchored month, padded with nils to full weeks.
    private var monthCells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: monthAnchor),
              let firstWeekday = cal.dateComponents([.weekday], from: interval.start).weekday else { return [] }
        let daysInMonth = cal.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<daysInMonth {
            cells.append(cal.date(byAdding: .day, value: d, to: interval.start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func events(on day: Date) -> [Event] {
        eventsByDay[cal.startOfDay(for: day)] ?? []
    }

    private var selectedDayEvents: [Event] {
        guard let day = selectedDay else { return [] }
        return events(on: day).sorted { $0.time < $1.time }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    monthHeader
                    weekdayRow
                    grid
                    selectedList
                }
                .padding(Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
            .background(VerdureBackground())
            .navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event, dateFormatter: dateFormatter)
                .environment(gameState).environment(locationManager)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { stepMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.ink).frame(width: 40, height: 40)
                    .background(ClayBackground(style: .surface, radius: Radius.chip, elevation: 0.5))
            }.buttonStyle(.plain)
            Spacer()
            Text(monthTitle).font(VType.display(22, .semibold)).foregroundStyle(Palette.ink)
            Spacer()
            Button { stepMonth(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.ink).frame(width: 40, height: 40)
                    .background(ClayBackground(style: .surface, radius: Radius.chip, elevation: 0.5))
            }.buttonStyle(.plain)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(VType.body(11, .bold)).foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                if let day = cell { dayCell(day) } else { Color.clear.frame(height: 44) }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let dayEvents = events(on: day)
        let isToday = cal.isDateInToday(day)
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let accent = dayEvents.first?.category.accent.base ?? Palette.teal.base
        return Button {
            Haptics.soft()
            withAnimation(.spring(response: 0.3)) { selectedDay = day }
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(VType.num(14, isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Palette.spruce.onColor : Palette.ink)
                HStack(spacing: 2) {
                    ForEach(0..<min(dayEvents.count, 3), id: \.self) { i in
                        Circle()
                            .fill(isSelected ? Palette.spruce.onColor : dayEvents[i].category.accent.base)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? Palette.spruce.base : (dayEvents.isEmpty ? Color.clear : accent.opacity(0.12)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(isToday && !isSelected ? Palette.gold.base : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var selectedList: some View {
        if let day = selectedDay {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(longDate(day)).font(VType.display(17, .semibold)).foregroundStyle(Palette.ink)
                if selectedDayEvents.isEmpty {
                    Text("No events this day.").font(VType.body(14)).foregroundStyle(Palette.inkSoft)
                        .padding(.vertical, Spacing.sm)
                } else {
                    ForEach(selectedDayEvents) { event in
                        Button { Haptics.soft(); selectedEvent = event } label: {
                            calendarEventRow(event)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        } else {
            Text("Tap a highlighted day to see its events.")
                .font(VType.body(14)).foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity).padding(.top, Spacing.md)
        }
    }

    private func calendarEventRow(_ event: Event) -> some View {
        HStack(spacing: Spacing.md) {
            ClayIconTile(systemImage: event.imagePlaceholder, kind: event.category.clayKind, size: 44, radius: Radius.chip)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(VType.display(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text("\(event.time) · \(event.locationName)")
                    .font(VType.body(12, .medium)).foregroundStyle(Palette.inkSoft).lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            PointsBadge(points: event.pointValue, kind: event.category.clayKind)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .claySurface(.surface, radius: Radius.md, elevation: 0.8)
    }

    private func stepMonth(_ delta: Int) {
        Haptics.soft()
        if let d = cal.date(byAdding: .month, value: delta, to: monthAnchor) {
            withAnimation(.spring(response: 0.35)) { monthAnchor = d; selectedDay = nil }
        }
    }

    private func longDate(_ day: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f.string(from: day)
    }
}
