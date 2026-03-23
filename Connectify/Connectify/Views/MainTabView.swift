import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ExploreView()
                .tabItem {
                    Label("Explore", systemImage: "safari.fill")
                }
                .tag(0)

            EventsView()
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }
                .tag(1)

            MapExploreView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(2)

            CommunityView()
                .tabItem {
                    Label("Community", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(3)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(4)
        }
        .tint(Color.connectifyGreen)
    }
}

#Preview {
    MainTabView()
}
