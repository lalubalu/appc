import SwiftUI
import FirebaseCore

@main
struct ConnectifyApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @AppStorage("lastDailyGemDate") private var lastDailyGemDate: String = ""
    @State private var gameState = GameStateManager()
    @State private var locationManager = LocationManager()
    @State private var authService: AuthService
    @State private var firestoreService: FirestoreService
    @State private var placesService = PlacesAPIService()
    @State private var eventsService = EventsAPIService()
    @State private var dailyGemPlace: Place?

    init() {
        FirebaseApp.configure()
        _authService = State(initialValue: AuthService())
        _firestoreService = State(initialValue: FirestoreService())
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
                    .environment(gameState)
                    .environment(locationManager)
                    .environment(authService)
                    .environment(firestoreService)
                    .environment(placesService)
                    .environment(eventsService)
                    .preferredColorScheme(prefersDarkMode ? .dark : .light)
                    .onAppear {
                        locationManager.requestPermission()
                        connectServicesIfNeeded()
                        checkDailyGem()
                    }
                    .onChange(of: authService.isAuthenticated) { _, isAuth in
                        if isAuth {
                            connectServicesIfNeeded()
                            checkDailyGem()
                        }
                    }
                    .fullScreenCover(item: $dailyGemPlace) { place in
                        DailyGemView(featuredPlace: place) {
                            dailyGemPlace = nil
                        }
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environment(authService)
                    .preferredColorScheme(.light)
            }
        }
    }

    /// Wire up Firestore sync and trigger initial places fetch after auth.
    private func connectServicesIfNeeded() {
        if let user = authService.currentUser {
            gameState.connectCloud(firestore: firestoreService, userID: user.uid)

            // Fetch places and events around user's location (or default center)
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

        // Pick the highest-rated place as the daily gem
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
