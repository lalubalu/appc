import SwiftUI
import FirebaseCore

@main
struct VerdureApp: App {
    init() {
        FirebaseApp.configure()
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
    @AppStorage("lastDailyGemDate") private var lastDailyGemDate: String = ""

    @State private var gameState = GameStateManager()
    @State private var locationManager = LocationManager()
    @State private var authService = AuthService()
    @State private var firestoreService = FirestoreService()
    @State private var placesService = PlacesAPIService()
    @State private var eventsService = EventsAPIService()
    @State private var dailyGemPlace: Place?

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
                    .onAppear {
                        locationManager.requestPermission()
                        connectServicesIfNeeded()
                        checkDailyGem()
                        if NotificationManager.shared.enabled {
                            Task { await NotificationManager.shared.requestPermission() }
                        }
                    }
                    .onChange(of: authService.isAuthenticated) { _, isAuth in
                        if isAuth {
                            connectServicesIfNeeded()
                            checkDailyGem()
                        }
                    }
                    .fullScreenCover(item: $dailyGemPlace) { place in
                        DailyGemView(featuredPlace: place) { dailyGemPlace = nil }
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environment(authService)
            }
        }
        .preferredColorScheme(prefersDarkMode ? .dark : .light)
    }

    /// Wire up Firestore sync and trigger initial places fetch after auth.
    private func connectServicesIfNeeded() {
        if let user = authService.currentUser {
            gameState.connectCloud(firestore: firestoreService, userID: user.uid)
            Task {
                let center = locationManager.userCoordinate
                await placesService.fetchNearbyPlaces(around: center)
                await eventsService.fetchNearbyEvents(around: center)
            }
        }
    }

    /// Show the Daily Gem splash on first login and once per calendar day.
    private func checkDailyGem() {
        let today = dailyGemDateString()
        guard lastDailyGemDate != today else { return }
        let gemPlace = placesService.places.max(by: { $0.rating < $1.rating })
            ?? SampleData.places.first!
        lastDailyGemDate = today
        dailyGemPlace = gemPlace
    }

    private func dailyGemDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
