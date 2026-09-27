import SwiftUI
import CoreLocation
import CoreImage.CIFilterBuiltins
@preconcurrency import FirebaseFunctions
@preconcurrency import FirebaseAuth

private enum AppTab: Int, CaseIterable {
    case discover, plan, friends, rewards, profile

    var title: String {
        switch self {
        case .discover: "Discover"
        case .plan:     "Plan"
        case .friends:  "Friends"
        case .rewards:  "Rewards"
        case .profile:   "Profile"
        }
    }

    var icon: String {
        switch self {
        case .discover: "safari.fill"
        case .plan:     "calendar.badge.clock"
        case .friends:  "person.2.fill"
        case .rewards:  "gift.fill"
        case .profile:   "person.fill"
        }
    }
}

private struct FriendInviteLink: Equatable {
    let uid: String
    let token: String
}

struct MainTabView: View {
    private enum DiscoverMode: String, CaseIterable { case events = "Events", places = "Places", map = "Map" }
    @State private var selected: AppTab
    @State private var discoverMode: DiscoverMode
    @State private var showCollectionOnLaunch = false
    @State private var communityOnLaunch = false
    @State private var router = DeepLinkRouter.shared
    @State private var deepLinkedEventId: BoxedID?
    @State private var friendInvite: FriendInviteLink?
    @State private var primerTrigger: NotificationPrimer.Trigger?
    @Environment(GameStateManager.self) private var gameState

    /// `sheet(item:)` needs an Identifiable; a bare String isn't one.
    struct BoxedID: Identifiable, Equatable { let id: String }

    /// Take whatever the router is holding and go there.
    private func consumeDeepLink() {
        guard let destination = router.claim() else { return }
        switch destination {
        case .event(let id):
            selected = .discover
            discoverMode = .events
            deepLinkedEventId = BoxedID(id: id)
        case .friendInvite(let uid, let token):
            selected = .friends
            friendInvite = FriendInviteLink(uid: uid, token: token)
        case .perk, .rewards:
            selected = .rewards
        case .notifications:
            selected = .profile
        }
    }

    init() {
        // QA hook (debug builds only): supports all five tabs plus the old
        // surface names so screenshot sweeps can still reach Collection, Map,
        // Places, and Community without scripted taps.
        var initial: AppTab = .discover
        var initialMode: DiscoverMode = .events
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "QATab") {
            switch raw.lowercased() {
            case "explore", "places": initial = .discover; initialMode = .places
            case "map": initial = .discover; initialMode = .map
            case "collect", "collection": initial = .profile
            case "community", "friends": initial = .friends
            case "plan": initial = .plan
            case "rewards": initial = .rewards
            case "profile": initial = .profile
            default: initial = .discover
            }
        }
        showCollectionOnLaunch = UserDefaults.standard.string(forKey: "QATab")?.lowercased() == "collect" ||
            UserDefaults.standard.string(forKey: "QATab")?.lowercased() == "collection"
        communityOnLaunch = UserDefaults.standard.string(forKey: "QATab")?.lowercased() == "community"
        #endif
        _selected = State(initialValue: initial)
        _discoverMode = State(initialValue: initialMode)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VerdureBackground().zIndex(-1)
            Group {
                switch selected {
                case .discover: discoverContent
                case .plan:     PlanTabView()
                case .friends:  FriendsTabView(initialCommunity: communityOnLaunch, invite: friendInvite)
                case .rewards:  RewardsStoreView(showsDoneButton: false)
                case .profile:   ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Animate the swap between tabs (each screen also replays its own
            // entrance choreography on appear).
            .id(selected)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 118) }

            ClayTabBar(selected: $selected)
        }
        .tint(Palette.spruce.base)
        .ignoresSafeArea(edges: .bottom)
        // Deep links from a tapped notification.
        //
        // Claimed on appear (the COLD-LAUNCH case: the tap was handled before
        // this view existed, and the destination has been waiting) and also
        // watched while running, so a tap taken with the app already open lands
        // just the same. `claim()` is idempotent, so the two paths cannot both
        // navigate for one tap.
        .onAppear { consumeDeepLink() }
        .onChange(of: router.pending) { _, _ in consumeDeepLink() }
        .sheet(item: $deepLinkedEventId) { boxed in
            EventDeepLinkSheet(eventId: boxed.id)
        }
        .sheet(isPresented: $showCollectionOnLaunch) { CollectionView() }
        // C3: permission priming, hosted here so any screen can trigger it by
        // setting the flag. Gated twice — a trigger must have fired AND iOS must
        // not already have been asked, because a second requestAuthorization
        // returns instantly without showing anything, so re-priming someone who
        // already answered is a sheet that leads nowhere.
        .sheet(item: $primerTrigger) { trigger in
            NotificationPrimer(trigger: trigger)
                .presentationDetents([.height(480)])
        }
        .onChange(of: gameState.pendingNotificationPrimer) { _, trigger in
            guard let trigger else { return }
            gameState.pendingNotificationPrimer = nil
            Task {
                let determined = await NotificationManager.authorizationDetermined()
                if NotificationPrimer.shouldPrime(authorizationDetermined: determined) {
                    primerTrigger = trigger
                }
            }
        }
    }

    private var discoverContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(DiscoverMode.allCases, id: \.self) { mode in
                    Button {
                        Haptics.soft()
                        withAnimation(.easeInOut(duration: 0.2)) { discoverMode = mode }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode == .events ? "calendar" : mode == .places ? "leaf" : "map")
                            Text(mode.rawValue)
                        }
                        .font(VType.body(13, .semibold))
                        .foregroundStyle(discoverMode == mode ? Palette.spruce.onColor : Palette.inkSoft)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background {
                            if discoverMode == mode {
                                RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.spruce.base)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(discoverMode == mode ? .isSelected : [])
                }
            }
            .padding(4)
            .background(ClayBackground(style: .surface, radius: Radius.md, elevation: 0.6))
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)

            Group {
                switch discoverMode {
                case .events: EventsView()
                case .places: ExploreView()
                case .map: MapExploreView()
                }
            }
            .id(discoverMode)
        }
    }
}

private struct ClayTabBar: View {
    @Binding var selected: AppTab
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 20
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                TabItemButton(tab: tab, isSelected: selected == tab, ns: indicator) {
                    Haptics.soft()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7)) {
                        selected = tab
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(ClayBackground(style: .surface, radius: Radius.lg, elevation: 1.15))
        .padding(.horizontal, 14)
        .padding(.bottom, bottomInset + 6)
    }
}

private struct TabItemButton: View {
    let tab: AppTab
    let isSelected: Bool
    let ns: Namespace.ID
    let action: () -> Void

    @State private var bounce = false

    var body: some View {
        Button {
            action()
            if !isSelected { bounce.toggle() }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        ClayBackground(style: .accent(.spruce), radius: Radius.chip, elevation: 0.55)
                            .frame(width: 46, height: 34)
                            .matchedGeometryEffect(id: "active", in: ns)
                    }
                    Image(systemName: tab.icon)
                        .font(.system(size: 19, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? Palette.spruce.onColor : Palette.inkSoft)
                        .symbolEffect(.bounce, value: bounce)
                        .scaleEffect(isSelected ? 1.06 : 1)
                }
                .frame(height: 34)

                Text(tab.title)
                    .font(VType.body(11, isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Palette.spruce.base : Palette.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plan from real listings

/// Plans use server-ranked, verified event IDs; the local path supports QA
/// when authentication or the live index is unavailable.
private struct PlanTabView: View {
    @Environment(EventsAPIService.self) private var eventsService
    @Environment(LocationManager.self) private var locationManager
    @Environment(SocialService.self) private var social
    @Environment(StoreService.self) private var store
    @State private var when = "This weekend"
    @State private var pickedDate = Date()
    @State private var company = "Just me"
    @State private var distance = "Short drive"
    @State private var budget = "Free"
    @State private var note = ""
    @State private var selectedIDs: [String] = []
    @State private var sessionID: String?
    @State private var planTitle = "Your plan"
    @State private var planIntro = ""
    @State private var planReasons: [String: String] = [:]
    @State private var planError: String?
    @State private var planning = false
    @State private var showPaywall = false
    @State private var showGroupPlans = false
    @State private var selectedEvent: Event?
    @State private var attempted = false
    @State private var showProfiles = false
    private let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private var pickedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: pickedDate)
    }

    private var candidates: [Event] {
        let calendar = Calendar.current
        let now = Date()
        return eventsService.events.filter { event in
            guard event.date >= now else { return false }
            let day = calendar.component(.weekday, from: event.date)
            let fitsWhen: Bool
            switch when {
            case "Tonight": fitsWhen = calendar.isDateInToday(event.date)
            case "Tomorrow": fitsWhen = calendar.isDateInTomorrow(event.date)
            case "This weekend": fitsWhen = day == 1 || day == 7
            case "Pick a date": fitsWhen = calendar.isDate(event.date, inSameDayAs: pickedDate)
            default: fitsWhen = true
            }
            let fitsBudget = budget != "Free" || event.isFree == true
            let underTwenty = budget != "Under $20" || event.isFree == true ||
                event.priceMin.map { $0 <= 20 } == true
            let familyText = "\(event.title) \(event.description ?? "") \(event.tags.joined(separator: " "))"
            let fitsCompany = company != "With kids" ||
                ["family", "kids", "children", "all ages"].contains(where: familyText.localizedCaseInsensitiveContains)
            let fitsDistance: Bool
            if distance == "Anywhere nearby" {
                fitsDistance = true
            } else if let venue = event.coordinate, let origin = locationManager.userLocation {
                let meters = CLLocation(latitude: venue.latitude, longitude: venue.longitude)
                    .distance(from: origin)
                fitsDistance = meters <= (distance == "Walking" ? 2_000 : 20_000)
            } else {
                fitsDistance = distance != "Walking"
            }
            let fitsNote = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                "\(event.title) \(event.description ?? "") \(event.locationName)".localizedCaseInsensitiveContains(note)
            return fitsWhen && fitsBudget && underTwenty && fitsCompany && fitsDistance && fitsNote
        }.sorted { left, right in
            if company == "Friends" {
                let leftFriends = social.friendsGoingByEvent[left.id]?.count ?? 0
                let rightFriends = social.friendsGoingByEvent[right.id]?.count ?? 0
                if leftFriends != rightFriends { return leftFriends > rightFriends }
            }
            let order = eventsService.rankedEventIDs
            let a = order.firstIndex(of: left.id) ?? Int.max
            let b = order.firstIndex(of: right.id) ?? Int.max
            return a == b ? left.date < right.date : a < b
        }
    }

    private var plannedEvents: [Event] {
        selectedIDs.compactMap { id in eventsService.events.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    optionsSection("When", choices: ["Tonight", "Tomorrow", "This weekend", "Pick a date"], selection: $when)
                    if when == "Pick a date" {
                        DatePicker("Choose a day", selection: $pickedDate, in: Date()..., displayedComponents: .date)
                            .font(VType.body(14, .semibold))
                            .tint(Palette.spruce.base)
                    }
                    optionsSection("Who with", choices: ["Just me", "Friends", "With kids"], selection: $company)
                    optionsSection("How far", choices: ["Walking", "Short drive", "Anywhere nearby"], selection: $distance)
                    optionsSection("Budget", choices: ["Free", "Under $20", "Doesn't matter"], selection: $budget)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Something specific?").font(VType.body(14, .semibold)).foregroundStyle(Palette.ink)
                        TextField("A workshop, live music, somewhere outdoors…", text: $note)
                            .font(VType.body(14))
                            .padding(14)
                            .background(ClayBackground(style: .inset, radius: Radius.sm))
                            .submitLabel(.done)
                    }
                    Button { Task { await makePlan() } } label: {
                        HStack {
                            Text(planning ? "Finding your plan…" : "Find real events")
                            Spacer()
                            if planning { ProgressView().tint(Palette.spruce.onColor) }
                            else { Image(systemName: "arrow.right") }
                        }
                            .font(VType.body(15, .semibold))
                            .foregroundStyle(Palette.spruce.onColor)
                            .padding(16)
                            .background(Palette.spruce.base, in: RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(planning)

                    if let planError {
                        Text(planError).font(VType.body(13)).foregroundStyle(Palette.inkSoft)
                    }

                    if company == "Friends" && social.friends.isEmpty {
                        Text("Add a friend in Friends to see who's going and plan together.")
                            .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                    }

                    if !selectedIDs.isEmpty {
                        HStack {
                            Text(planTitle).font(VType.display(28, .semibold)).foregroundStyle(Palette.ink)
                            Spacer()
                            Button("Shorter") { Task { await refine("shorter") } }
                                .font(VType.body(12, .semibold))
                                .disabled(selectedIDs.count < 2)
                        }
                        if !planIntro.isEmpty {
                            Text(planIntro).font(VType.body(13)).foregroundStyle(Palette.inkSoft)
                        }
                        ForEach(Array(plannedEvents.enumerated()), id: \.element.id) { index, event in
                            planCard(event, number: index + 1)
                        }
                        if sessionID != nil {
                            Button { showGroupPlans = true } label: {
                                Label("Plan with friends", systemImage: "person.2.fill")
                                    .font(VType.body(14, .semibold))
                                    .frame(maxWidth: .infinity).padding(14)
                                    .foregroundStyle(Palette.spruce.base)
                                    .claySurface(.surface, radius: Radius.md)
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 20) {
                            Button("Longer") { Task { await refine("longer") } }
                            Button("Different vibe") { Task { await refine("different", targetID: selectedIDs.first) } }
                        }
                        .font(VType.body(13, .semibold)).foregroundStyle(Palette.spruce.base)
                    } else if attempted || eventsService.events.isEmpty {
                        EmptyStateCard(icon: "calendar.badge.exclamationmark",
                                       title: eventsService.events.isEmpty ? "The local calendar is still filling in" : "No events fit those choices yet",
                                       message: eventsService.events.isEmpty
                                           ? "Plans use real events only. Check back when nearby listings are available."
                                           : "Try another day, a wider distance, or a different budget.")
                    }
                }
                .padding(Spacing.md)
                .padding(.bottom, 110)
            }
            .background(VerdureBackground())
            .task {
                await eventsService.fetchNearbyEvents(around: locationManager.userCoordinate,
                                                      followedOrganizerIDs: social.followedOrganizerIDs)
                if company == "Friends" {
                    await social.loadFriendsGoing(for: Array(eventsService.events.prefix(50)).map(\.id))
                }
            }
            .onChange(of: company) { _, value in
                if value == "Friends" {
                    Task { await social.loadFriendsGoing(for: Array(eventsService.events.prefix(50)).map(\.id)) }
                }
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailSheet(event: event, dateFormatter: eventDateFormatter)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showProfiles) { InterestProfilesSheet() }
            .sheet(isPresented: $showPaywall) { PaywallView(source: "planner") }
            .sheet(isPresented: $showGroupPlans) { GroupPlansSheet(sessionID: sessionID) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            KickerLabel(text: "MAKE ROOM FOR OUTSIDE", color: Palette.spruce.base, dot: Palette.spruce.base)
            Text("Make a plan.").font(VType.display(38, .semibold)).foregroundStyle(Palette.ink)
            Text("A few choices. Real things happening nearby.")
                .font(VType.body(14)).foregroundStyle(Palette.inkSoft)
            Button { showGroupPlans = true } label: {
                Label("Your group plans", systemImage: "person.2.circle")
                    .font(VType.body(13, .semibold)).foregroundStyle(Palette.spruce.base)
            }.buttonStyle(.plain)
            if store.isPlus {
                Button { showProfiles = true } label: {
                    Label("Switch interest profile", systemImage: "square.stack.3d.up")
                        .font(VType.body(13, .semibold)).foregroundStyle(Palette.spruce.base)
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    private func optionsSection(_ title: String, choices: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(VType.body(14, .semibold)).foregroundStyle(Palette.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(choices, id: \.self) { choice in
                        Button { selection.wrappedValue = choice; Haptics.soft() } label: {
                            Text(choice)
                                .font(VType.body(13, .medium))
                                .foregroundStyle(selection.wrappedValue == choice ? Palette.spruce.onColor : Palette.ink)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(selection.wrappedValue == choice ? Palette.spruce.base : Palette.surface,
                                            in: RoundedRectangle(cornerRadius: Radius.sm))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection.wrappedValue == choice ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func makePlan() async {
        attempted = true
        planError = nil
        guard Auth.auth().currentUser != nil, !QAData.offline else {
            selectedIDs = Array(candidates.prefix(2).map(\.id))
            sessionID = nil
            planTitle = "A plan nearby"
            planIntro = "Real events that fit your choices."
            return
        }
        planning = true
        defer { planning = false }
        do {
            let coord = locationManager.userCoordinate
            let area = LaunchArea.nearest(to: coord, in: eventsService.launchAreas)?.id ?? "san-jose-ca"
            let payload: [String: any Sendable] = [
                "when": when, "targetDate": when == "Pick a date" ? pickedDateString : "",
                "who": company, "distance": distance,
                "budget": budget, "note": note, "areaId": area,
                "lat": coord.latitude, "lng": coord.longitude
            ]
            let response = try await Functions.functions().httpsCallable("planEvents").call(payload)
            guard let data = response.data as? [String: Any],
                  let id = data["sessionId"] as? String,
                  let stops = data["stops"] as? [[String: Any]] else {
                throw NSError(domain: "VerdurePlanner", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "The plan could not be loaded."])
            }
            let ids = stops.compactMap { $0["eventId"] as? String }
            await eventsService.ensureEvents(ids)
            selectedIDs = ids.filter { selectedID in eventsService.events.contains { $0.id == selectedID } }
            sessionID = id
            planTitle = data["title"] as? String ?? "Your plan"
            planIntro = data["intro"] as? String ?? ""
            planReasons = Dictionary(uniqueKeysWithValues: stops.compactMap { row in
                guard let id = row["eventId"] as? String else { return nil }
                return (id, row["why"] as? String ?? "")
            })
            Haptics.soft()
        } catch {
            selectedIDs = []
            let ns = error as NSError
            if ns.localizedDescription.localizedCaseInsensitiveContains("monthly free plans") ||
                ns.localizedDescription.localizedCaseInsensitiveContains("quota") {
                showPaywall = true
                planError = "Your monthly free plans are used. Verdure+ has unlimited plans."
            } else {
                planError = error.localizedDescription
            }
        }
    }

    private func refine(_ action: String, targetID: String? = nil) async {
        guard let sessionID else {
            if action == "shorter", selectedIDs.count > 1 { selectedIDs.removeLast() }
            return
        }
        guard !planning else { return }
        planning = true
        defer { planning = false }
        do {
            let payload: [String: any Sendable] = [
                "sessionId": sessionID, "action": action, "targetId": targetID ?? ""
            ]
            let response = try await Functions.functions().httpsCallable("refineEventPlan").call(payload)
            guard let data = response.data as? [String: Any],
                  let ids = data["selectedIDs"] as? [String] else { return }
            await eventsService.ensureEvents(ids)
            selectedIDs = ids.filter { id in eventsService.events.contains { $0.id == id } }
            planError = nil
            Haptics.soft()
        } catch {
            planError = error.localizedDescription
        }
    }

    private func planCard(_ event: Event, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(String(format: "%02d", number))
                    .font(VType.num(24, .bold)).foregroundStyle(Palette.spruce.base)
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.title).font(VType.display(20, .semibold)).foregroundStyle(Palette.ink)
                    Text("\(event.date.formatted(date: .abbreviated, time: .shortened)) · \(event.locationName)")
                        .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                    Text(event.priceLabel ?? "Price not listed")
                        .font(VType.body(12, .semibold)).foregroundStyle(Palette.spruce.base)
                    if let going = social.friendsGoingByEvent[event.id], going.count > 0 {
                        Text("\(going.count) friend\(going.count == 1 ? "" : "s") going")
                            .font(VType.body(12, .semibold)).foregroundStyle(Palette.spruce.base)
                    }
                    if let why = planReasons[event.id], !why.isEmpty {
                        Text(why).font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("Details") { selectedEvent = event }
                GoingButton(event: event)
                Spacer()
                Menu("Refine") {
                    ForEach(["Swap", "Earlier", "Later", "Cheaper", "Closer", "More like this", "Remove"], id: \.self) { label in
                        Button(label) {
                            let action = label == "More like this" ? "more" : label.lowercased()
                            Task { await refine(action, targetID: event.id) }
                        }
                    }
                }
            }
            .font(VType.body(12, .semibold)).foregroundStyle(Palette.spruce.base)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .claySurface(.surface, radius: Radius.md, elevation: 0.8)
    }
}

// MARK: - Shared plans

private struct GroupPlanSummary: Identifiable {
    let id: String
    let title: String
    let ownerUID: String
    let eventIDs: [String]
    let memberCount: Int
    let pendingCount: Int
    let votes: [String: Int]
    let myVotes: [String]
    let invitation: Bool

    init?(_ data: [String: Any]) {
        guard let id = data["id"] as? String else { return nil }
        self.id = id
        title = data["title"] as? String ?? "A plan together"
        ownerUID = data["ownerUid"] as? String ?? ""
        eventIDs = data["eventIDs"] as? [String] ?? []
        memberCount = data["memberCount"] as? Int ?? 1
        pendingCount = data["pendingCount"] as? Int ?? 0
        votes = data["votes"] as? [String: Int] ?? [:]
        myVotes = data["myVotes"] as? [String] ?? []
        invitation = data["invitation"] as? Bool ?? false
    }
}

private struct GroupPlansSheet: View {
    let sessionID: String?
    @Environment(EventsAPIService.self) private var eventsService
    @Environment(SocialService.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var plans: [GroupPlanSummary] = []
    @State private var selectedID: String?
    @State private var error: String?
    @State private var working = false
    @State private var selectedEvent: Event?
    private var selected: GroupPlanSummary? { plans.first { $0.id == selectedID } }
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "EEE, MMM d"; return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Make room for everyone.")
                        .font(VType.display(28, .semibold)).foregroundStyle(Palette.ink)
                    Text("Invite accepted friends, shortlist real events, then each person chooses their own RSVP.")
                        .font(VType.body(13)).foregroundStyle(Palette.inkSoft)
                    if let sessionID {
                        Button { Task { await act("create", extra: ["sessionId": sessionID]) } } label: {
                            Label("Share the current plan", systemImage: "person.2.badge.plus")
                                .font(VType.body(14, .semibold)).foregroundStyle(Palette.spruce.onColor)
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Palette.spruce.base, in: RoundedRectangle(cornerRadius: Radius.md))
                        }
                        .buttonStyle(.plain).disabled(working)
                    }
                    if let error { Text(error).font(VType.body(12)).foregroundStyle(Palette.danger) }
                    ForEach(plans) { plan in
                        Button { selectedID = plan.id; Task { await eventsService.ensureEvents(plan.eventIDs) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(plan.title).font(VType.body(15, .semibold)).foregroundStyle(Palette.ink)
                                    Text(plan.invitation ? "Invitation · choose to join" : "\(plan.memberCount) planning · \(plan.eventIDs.count) events")
                                        .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                                }
                                Spacer()
                                Image(systemName: selectedID == plan.id ? "chevron.down" : "chevron.right")
                                    .foregroundStyle(Palette.spruce.base)
                            }
                            .padding(Spacing.md).claySurface(.surface, radius: Radius.md)
                        }
                        .buttonStyle(.plain)
                    }
                    if let plan = selected { details(plan) }
                }
                .padding(Spacing.md)
            }
            .background(VerdureBackground())
            .navigationTitle("Group plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $selectedEvent) { event in
                EventDetailSheet(event: event, dateFormatter: dateFormatter)
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func details(_ plan: GroupPlanSummary) -> some View {
        if plan.invitation {
            HStack {
                Button("Decline") { Task { await act("respond", extra: ["planId": plan.id, "accept": false]) } }
                Spacer()
                Button("Join plan") { Task { await act("respond", extra: ["planId": plan.id, "accept": true]) } }
            }
            .font(VType.body(14, .semibold)).foregroundStyle(Palette.spruce.base)
            .padding(Spacing.md).claySurface(.surface, radius: Radius.md)
        } else {
            if plan.ownerUID == Auth.auth().currentUser?.uid {
                Menu {
                    ForEach(social.friends) { friend in
                        Button(friend.displayName) {
                            Task { await act("invite", extra: ["planId": plan.id, "peerUid": friend.uid]) }
                        }
                    }
                } label: {
                    Label("Invite a friend", systemImage: "person.crop.circle.badge.plus")
                        .font(VType.body(14, .semibold)).foregroundStyle(Palette.spruce.base)
                }
                if social.friends.isEmpty {
                    Text("Add an accepted friend in Friends to invite them here.")
                        .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                }
            }
            ForEach(plan.eventIDs, id: \.self) { id in
                if let event = eventsService.events.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(event.title).font(VType.display(19, .semibold)).foregroundStyle(Palette.ink)
                        Text("\(event.date.formatted(date: .abbreviated, time: .shortened)) · \(event.locationName)")
                            .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                        HStack {
                            Button(plan.myVotes.contains(id) ? "Shortlisted · \(plan.votes[id] ?? 0)" : "Shortlist · \(plan.votes[id] ?? 0)") {
                                Task { await act("vote", extra: ["planId": plan.id, "eventId": id]) }
                            }
                            Spacer()
                            Button("Details") { selectedEvent = event }
                            GoingButton(event: event, compact: true)
                        }
                        .font(VType.body(12, .semibold)).foregroundStyle(Palette.spruce.base)
                    }
                    .padding(Spacing.md).claySurface(.surface, radius: Radius.md)
                }
            }
            if plan.ownerUID == Auth.auth().currentUser?.uid {
                Button("Delete group plan") { Task { await act("delete", extra: ["planId": plan.id]) } }
                    .font(VType.body(12)).foregroundStyle(Palette.danger)
            }
        }
    }

    private func load() async {
        guard Auth.auth().currentUser != nil else {
            error = "Sign in to plan with friends."; return
        }
        do {
            let payload: [String: any Sendable] = ["action": "list"]
            let response = try await Functions.functions().httpsCallable("manageGroupPlan").call(payload)
            let rows = (response.data as? [String: Any])?["plans"] as? [[String: Any]] ?? []
            plans = rows.compactMap(GroupPlanSummary.init)
        } catch { self.error = error.localizedDescription }
    }

    private func act(_ action: String, extra: [String: any Sendable]) async {
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            var payload: [String: any Sendable] = ["action": action]
            for (key, value) in extra { payload[key] = value }
            let response = try await Functions.functions().httpsCallable("manageGroupPlan").call(payload)
            if let row = (response.data as? [String: Any])?["plan"] as? [String: Any],
               let plan = GroupPlanSummary(row) {
                selectedID = plan.id
                await eventsService.ensureEvents(plan.eventIDs)
            } else if action == "delete" || action == "respond" {
                selectedID = nil
            }
            await load()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Friends and community

private struct FriendsTabView: View {
    let initialCommunity: Bool
    let invite: FriendInviteLink?
    @Environment(SocialService.self) private var social
    @Environment(EventsAPIService.self) private var eventsService
    @Environment(AuthService.self) private var auth
    @State private var showsCommunity = false
    @State private var showNotifications = false
    @State private var showAddFriend = false
    @State private var showLeaderboard = false
    @State private var showGroupPlans = false
    @State private var showAuth = false
    @State private var selectedEvent: MainTabView.BoxedID?
    @State private var username = ""
    @State private var foundFriend: FriendSummary?
    @State private var searching = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()

    init(initialCommunity: Bool = false, invite: FriendInviteLink? = nil) {
        self.initialCommunity = initialCommunity
        self.invite = invite
        _showsCommunity = State(initialValue: initialCommunity)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Together, nearby.")
                        .font(VType.display(28, .semibold)).foregroundStyle(Palette.ink)
                    Text("Good plans are better shared.")
                        .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                Button { showNotifications = true } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Palette.spruce.base)
                        .frame(width: 44, height: 44)
                        .background(ClayBackground(style: .surface, radius: Radius.sm))
                }
                .accessibilityLabel("Invitations and notifications")
            }
            .padding(.horizontal, Spacing.md).padding(.top, 12)
            Picker("Friends section", selection: $showsCommunity) {
                Text("Friends").tag(false)
                Text("Community").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md).padding(.vertical, 12)

            if showsCommunity {
                CommunityView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if auth.currentUser == nil {
                            friendCard("Your people are waiting", message: "Sign in to add friends and share real plans.")
                            Button { showAuth = true } label: {
                                Text("Sign in to Friends")
                                    .font(VType.body(15, .semibold)).foregroundStyle(Palette.spruce.onColor)
                                    .frame(maxWidth: .infinity).padding(14)
                                    .background(Palette.spruce.base, in: RoundedRectangle(cornerRadius: Radius.sm))
                            }
                        } else {
                            if social.friends.isEmpty {
                                friendCard("Find your people here.", message: "Share a private invite to start planning together. Only people you accept can see your activity.")
                            }
                            Button { showAddFriend = true } label: {
                                Label("Add friends", systemImage: "person.crop.circle.badge.plus")
                                    .font(VType.body(15, .semibold)).foregroundStyle(Palette.spruce.onColor)
                                    .frame(maxWidth: .infinity).padding(14)
                                    .background(Palette.spruce.base, in: RoundedRectangle(cornerRadius: Radius.sm))
                            }
                            Button { showGroupPlans = true } label: {
                                Label("Group plans and invitations", systemImage: "calendar.badge.clock")
                                    .font(VType.body(14, .semibold)).foregroundStyle(Palette.spruce.base)
                                    .frame(maxWidth: .infinity).padding(14)
                                    .claySurface(.surface, radius: Radius.md)
                            }
                            .buttonStyle(.plain)
                            if !social.incomingFriendRequests.isEmpty { requestsSection }
                            goingSection
                            if !social.pendingInvites.isEmpty { invitesSection }
                            if !social.friends.isEmpty { friendsSection }
                            Button { showLeaderboard = true } label: {
                                Label("Friends leaderboard", systemImage: "chart.bar.xaxis")
                                    .font(VType.body(15, .semibold)).foregroundStyle(Palette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(Spacing.md)
                                    .claySurface(.surface, radius: Radius.md, elevation: 0.6)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(Spacing.md).padding(.bottom, 110)
                }
                .background(VerdureBackground())
            }
        }
        .background(VerdureBackground())
        .sheet(isPresented: $showNotifications) { NotificationsInboxView() }
        .sheet(isPresented: $showAuth) { AuthView(onComplete: { showAuth = false }) }
        .sheet(isPresented: $showAddFriend) { addFriendSheet }
        .sheet(isPresented: $showLeaderboard) { StatsAndLeaderboardView() }
        .sheet(isPresented: $showGroupPlans) { GroupPlansSheet(sessionID: nil) }
        .sheet(item: $selectedEvent) { EventDeepLinkSheet(eventId: $0.id) }
        .task {
            guard auth.currentUser != nil else { return }
            await social.refreshAll()
            await social.loadFriendInvite()
            await social.loadFriendsUpcoming()
            await social.loadFriendsGoing(for: Array(eventsService.events.prefix(50)).map(\.id))
        }
        .onChange(of: eventsService.events.map(\.id)) { _, ids in
            Task { await social.loadFriendsGoing(for: Array(ids.prefix(50))) }
        }
        .onAppear { if invite != nil { showAddFriend = true } }
        .onChange(of: invite) { _, newValue in if newValue != nil { showAddFriend = true } }
    }

    private func friendCard(_ title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 30)).foregroundStyle(Palette.spruce.base)
            Text(title).font(VType.display(24, .semibold)).foregroundStyle(Palette.ink)
            Text(message).font(VType.body(14)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .claySurface(.surface, radius: Radius.lg, elevation: 0.8)
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Friend requests").font(VType.display(21, .semibold)).foregroundStyle(Palette.ink)
            ForEach(social.incomingFriendRequests) { request in
                HStack {
                    Text(request.peerName).font(VType.body(15, .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Button("Decline") { Task { _ = await social.respondToFriendRequest(from: request.peerUid, accept: false) } }
                        .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                    Button("Accept") { Task { _ = await social.respondToFriendRequest(from: request.peerUid, accept: true) } }
                        .font(VType.body(12, .semibold)).foregroundStyle(Palette.spruce.base)
                }
                .padding(Spacing.md).claySurface(.surface, radius: Radius.md, elevation: 0.4)
            }
        }
    }

    private var goingSection: some View {
        let upcoming = social.friendsUpcoming.prefix(10)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Going soon").font(VType.display(21, .semibold)).foregroundStyle(Palette.ink)
            if upcoming.isEmpty {
                Text(social.friends.isEmpty ? "Add a friend to see their upcoming plans." : "No shared plans yet. Check back as friends RSVP.")
                    .font(VType.body(13)).foregroundStyle(Palette.inkSoft)
            }
            ForEach(Array(upcoming)) { event in
                Button { selectedEvent = .init(id: event.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title).font(VType.body(15, .semibold)).foregroundStyle(Palette.ink)
                        Text("\(event.friendNames.joined(separator: ", ")) · \(event.startsAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md).claySurface(.surface, radius: Radius.md, elevation: 0.4)
                }.buttonStyle(.plain)
            }
        }
    }

    private var invitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Invitations").font(VType.display(21, .semibold)).foregroundStyle(Palette.ink)
            ForEach(social.pendingInvites) { invite in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(invite.eventTitle).font(VType.body(14, .semibold)).foregroundStyle(Palette.ink)
                        Text("From \(invite.fromName)").font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                    }
                    Spacer()
                    Button("Decline") { Task { await social.declineInvite(invite.id) } }
                        .font(VType.body(12)).foregroundStyle(Palette.inkSoft)
                    Button("View") { selectedEvent = .init(id: invite.eventId) }
                        .font(VType.body(12, .semibold)).foregroundStyle(Palette.spruce.base)
                }
                .padding(Spacing.md).claySurface(.surface, radius: Radius.md, elevation: 0.4)
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your friends").font(VType.display(21, .semibold)).foregroundStyle(Palette.ink)
            ForEach(social.friends) { friend in
                HStack {
                    Text(friend.displayName).font(VType.body(14, .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Menu {
                        Button("Remove friend", role: .destructive) {
                            Task { _ = await social.removeFriend(friend.uid) }
                        }
                    } label: { Image(systemName: "ellipsis").foregroundStyle(Palette.inkSoft).frame(width: 44, height: 44) }
                }
                .padding(.leading, Spacing.md).claySurface(.surface, radius: Radius.md, elevation: 0.4)
            }
        }
    }

    private var addFriendSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Invite someone you know").font(VType.display(24, .semibold)).foregroundStyle(Palette.ink)
                    Text("Share this private link or show its QR code. You choose whether to accept a request.")
                        .font(VType.body(14)).foregroundStyle(Palette.inkSoft)
                    if let url = social.friendInviteURL {
                        if let qr = qrImage(url.absoluteString) {
                            Image(uiImage: qr).interpolation(.none).resizable()
                                .frame(width: 190, height: 190).frame(maxWidth: .infinity)
                                .accessibilityLabel("Private friend invite QR code")
                        }
                        ShareLink(item: url) {
                            Label("Share invite", systemImage: "square.and.arrow.up")
                                .font(VType.body(15, .semibold)).foregroundStyle(Palette.spruce.onColor)
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Palette.spruce.base, in: RoundedRectangle(cornerRadius: Radius.sm))
                        }
                    }
                    if let invite {
                        Button("Send request from invite") {
                            Task {
                                if await social.sendFriendRequest(to: invite.uid, inviteToken: invite.token) {
                                    showAddFriend = false
                                }
                            }
                        }
                        .font(VType.body(15, .semibold))
                        .foregroundStyle(Palette.spruce.base)
                    }
                    Text("Find an adult by exact username")
                        .font(VType.display(19, .semibold)).foregroundStyle(Palette.ink)
                    HStack {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(VType.body(15)).padding(12)
                            .claySurface(.surface, radius: Radius.sm, elevation: 0.3)
                        Button("Find") {
                            searching = true; foundFriend = nil
                            Task { foundFriend = await social.findFriend(username: username); searching = false }
                        }.disabled(username.count < 3 || searching)
                    }
                    if let foundFriend {
                        HStack {
                            Text(foundFriend.displayName).font(VType.body(15)).foregroundStyle(Palette.ink)
                            Spacer()
                            Button("Request") { Task { _ = await social.sendFriendRequest(to: foundFriend.uid); self.foundFriend = nil } }
                                .font(VType.body(14, .semibold)).foregroundStyle(Palette.spruce.base)
                        }.padding(Spacing.md).claySurface(.surface, radius: Radius.sm, elevation: 0.3)
                    }
                    if auth.ageRegistrationPending {
                        DatePicker("Confirm birth date", selection: $birthDate,
                                   in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!, displayedComponents: .date)
                        Button("Finish age protection") {
                            Task { _ = await auth.retryAgeRegistration(birthYear: Calendar.current.component(.year, from: birthDate)) }
                        }
                    }
                    if let error = social.lastError ?? auth.errorMessage {
                        Text(error).font(VType.body(12)).foregroundStyle(Palette.danger)
                    }
                }
                .padding(Spacing.lg)
            }
            .background(VerdureBackground())
            .navigationTitle("Add friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showAddFriend = false } } }
        }
    }

    private func qrImage(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        guard let image = filter.outputImage else { return nil }
        let scaled = image.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    MainTabView()
        .environment(GameStateManager())
        .environment(LocationManager())
        .environment(AuthService())
        .environment(FirestoreService())
        .environment(PlacesAPIService())
        .environment(EventsAPIService())
}
