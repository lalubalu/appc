import SwiftUI

private enum AppTab: Int, CaseIterable {
    case events, explore, map, collect, community, profile

    var title: String {
        switch self {
        case .events:    "Events"
        case .explore:   "Explore"
        case .map:       "Map"
        case .collect:   "Collect"
        case .community: "Community"
        case .profile:   "Profile"
        }
    }

    var icon: String {
        switch self {
        case .events:    "calendar"
        case .explore:   "safari.fill"        // compass — on brand
        case .map:       "map.fill"
        case .collect:   "leaf.fill"
        case .community: "bubble.left.and.bubble.right.fill"
        case .profile:   "person.fill"
        }
    }
}

struct MainTabView: View {
    @State private var selected: AppTab
    @State private var router = DeepLinkRouter.shared
    @State private var deepLinkedEventId: BoxedID?
    @State private var primerTrigger: NotificationPrimer.Trigger?
    @Environment(GameStateManager.self) private var gameState

    /// `sheet(item:)` needs an Identifiable; a bare String isn't one.
    struct BoxedID: Identifiable, Equatable { let id: String }

    /// Take whatever the router is holding and go there.
    private func consumeDeepLink() {
        guard let destination = router.claim() else { return }
        switch destination {
        case .event(let id):
            selected = .events
            deepLinkedEventId = BoxedID(id: id)
        case .perk, .rewards:
            selected = .collect
        case .notifications:
            selected = .profile
        }
    }

    init() {
        // QA hook (debug builds only): `-QATab collect` as a launch argument lands
        // in the NSArgumentDomain and selects the initial tab, so UI tests and
        // simctl screenshot sweeps can open any screen without scripted taps.
        var initial: AppTab = .events
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "QATab") {
            switch raw.lowercased() {
            case "explore": initial = .explore
            case "map": initial = .map
            case "collect": initial = .collect
            case "community": initial = .community
            case "profile": initial = .profile
            default: initial = .events
            }
        }
        #endif
        _selected = State(initialValue: initial)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VerdureBackground().zIndex(-1)
            Group {
                switch selected {
                case .events:    EventsView()
                case .explore:   ExploreView()
                case .map:       MapExploreView()
                case .collect:   CollectionView()
                case .community: CommunityView()
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
}

private struct ClayTabBar: View {
    @Binding var selected: AppTab
    @Namespace private var indicator

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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
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
                        .font(.system(size: 18, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? Palette.spruce.onColor : Palette.inkFaint)
                        .symbolEffect(.bounce, value: bounce)
                        .scaleEffect(isSelected ? 1.06 : 1)
                }
                .frame(height: 34)

                Text(tab.title)
                    .font(VType.body(9.5, isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Palette.spruce.base : Palette.inkFaint)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
