import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            EventsView()
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }
                .tag(0)

            ExploreView()
                .tabItem {
                    Label("Explore", systemImage: "safari.fill")
                }
                .tag(1)

            MapExploreView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(2)

            CollectionView()
                .tabItem {
                    Label("Collect", systemImage: "trophy.fill")
                }
                .tag(3)

            CommunityView()
                .tabItem {
                    Label("Community", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(4)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(5)
        }
        .tint(Color.connectifyGreen)
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
