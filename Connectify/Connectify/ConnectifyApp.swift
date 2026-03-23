import SwiftUI

@main
struct ConnectifyApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @State private var gameState = GameStateManager()
    @State private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
                    .environment(gameState)
                    .environment(locationManager)
                    .preferredColorScheme(prefersDarkMode ? .dark : .light)
                    .onAppear {
                        locationManager.requestPermission()
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .preferredColorScheme(.light)
            }
        }
    }
}
