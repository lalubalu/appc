import SwiftUI
import FirebaseCore

@main
struct VerdureApp: App {
    // Required for remote push: SwiftUI exposes no hook for the APNs device
    // token callback, and FCM can't route to a token it never sees.
    @UIApplicationDelegateAdaptor(VerdureAppDelegate.self) private var appDelegate

    init() {
        FirebaseApp.configure()
        PushService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Root view — owns app-wide state and drives the color scheme. Keeping the
/// @AppStorage here (in a View, not the App struct) makes the light/dark
/// toggle update reliably and apply at launch.
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var gameState = GameStateManager()
    @State private var locationManager = LocationManager()
    @State private var authService = AuthService()
    @State private var firestoreService = FirestoreService()
    @State private var functionsService = FunctionsService()
    @State private var placesService = PlacesAPIService()
    @State private var eventsService = EventsAPIService()
    @State private var storeService = StoreService()
    @State private var moderationService = ModerationService()
    @State private var socialService = SocialService()
    @State private var economyService = EconomyService()
    @State private var discoveryFilters = DiscoveryFilters()
    @State private var dailyGemFact: GemFact?

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
                    .environment(gameState)
                    .environment(locationManager)
                    .environment(authService)
                    .environment(firestoreService)
                    .environment(placesService)
                    .environment(eventsService)
                    .environment(storeService)
                    .environment(moderationService)
                    .environment(socialService)
                    .environment(economyService)
                    .environment(discoveryFilters)
                    .onAppear {
                        locationManager.requestPermission()
                        connectServicesIfNeeded()
                        gameState.recordActiveDay()   // real daily streak
                        checkDailyGem()
                        if NotificationManager.shared.enabled {
                            Task { await NotificationManager.shared.requestPermission() }
                        }
                    }
                    .onChange(of: authService.isAuthenticated) { _, isAuth in
                        if isAuth {
                            connectServicesIfNeeded()
                            checkDailyGem()
                        } else {
                            gameState.disconnectCloud()
                            moderationService.clearLocal()
                            socialService.clearLocal()
                        }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        guard phase == .active else { return }
                        gameState.recordActiveDay()   // streak counts foregrounds across days
                        // First foreground of a new day → show the Daily Gem.
                        checkDailyGem()
                        // Retry any earn-ops queued while offline.
                        Task { await gameState.flushPendingOps() }
                    }
                    .fullScreenCover(item: $dailyGemFact) { fact in
                        DailyGemView(fact: fact) { dailyGemFact = nil }
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environment(authService)
                    .environment(discoveryFilters)
            }
        }
        .preferredColorScheme(prefersDarkMode ? .dark : .light)
    }

    /// Wire up Firestore sync + server callables and trigger initial fetches after auth.
    private func connectServicesIfNeeded() {
        if let user = authService.currentUser {
            gameState.connectCloud(firestore: firestoreService, functions: functionsService, userID: user.uid)
            Task { await moderationService.refreshBlocks() }
            Task { await socialService.refreshAll() }
            Task {
                let center = locationManager.userCoordinate
                await placesService.fetchNearbyPlaces(around: center)
                await eventsService.fetchNearbyEvents(around: center)
            }
        }
    }

    /// Show the Daily Gem fun fact once per calendar day, on the first open of the day.
    private func checkDailyGem() {
        guard DailyGemStore.shouldShowSplash else { return }
        DailyGemStore.markSplashShown()
        let fact = DailyGemStore.todaysFact
        dailyGemFact = fact
        NotificationManager.shared.push(AppNotification(
            kind: .gem, title: "Today's Daily Gem",
            message: fact.text, timeAgo: "now"))
    }
}
