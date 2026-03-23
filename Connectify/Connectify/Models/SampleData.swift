import Foundation
import SwiftUI
import CoreLocation

// MARK: - Sample Data (placeholders for backend integration)

enum SampleData {

    // MARK: Places

    static let places: [Place] = [
        Place(name: "Riverside Park", category: .parks, shortDescription: "A sprawling green space along the river with walking paths and picnic areas.", distance: "0.3 mi", distanceValue: 0.3, rating: 4.8, reviewCount: 124, imagePlaceholder: "leaf.fill", accentColor: .connectifyGreen, isFeatured: true),
        Place(name: "Hawk Ridge Trail", category: .trails, shortDescription: "Moderate 2.4-mile loop with panoramic views of the valley.", distance: "1.2 mi", distanceValue: 1.2, rating: 4.6, reviewCount: 89, imagePlaceholder: "figure.hiking", accentColor: .accentAmber, isFeatured: false),
        Place(name: "Botanica Gardens", category: .gardens, shortDescription: "Community-maintained botanical garden with 200+ plant species.", distance: "0.8 mi", distanceValue: 0.8, rating: 4.9, reviewCount: 201, imagePlaceholder: "camera.macro", accentColor: .accentCoral, isFeatured: true),
        Place(name: "Lakeshore Playground", category: .playgrounds, shortDescription: "Modern playground with climbing structures and splash pad.", distance: "0.5 mi", distanceValue: 0.5, rating: 4.4, reviewCount: 67, imagePlaceholder: "figure.play", accentColor: .accentSky, isFeatured: false),
        Place(name: "Marina Point", category: .waterfront, shortDescription: "Scenic waterfront with kayak rentals and sunset viewing deck.", distance: "2.1 mi", distanceValue: 2.1, rating: 4.7, reviewCount: 156, imagePlaceholder: "water.waves", accentColor: .accentSky, isFeatured: true),
        Place(name: "Cedar Court Complex", category: .sports, shortDescription: "Public courts for basketball, tennis, and pickleball.", distance: "0.6 mi", distanceValue: 0.6, rating: 4.3, reviewCount: 45, imagePlaceholder: "sportscourt.fill", accentColor: .accentCoral, isFeatured: false),
        Place(name: "Overlook Bluff", category: .scenic, shortDescription: "The highest point in the county with 360° views.", distance: "3.4 mi", distanceValue: 3.4, rating: 4.9, reviewCount: 312, imagePlaceholder: "mountain.2.fill", accentColor: .accentLavender, isFeatured: true),
        Place(name: "The Commons", category: .community, shortDescription: "Outdoor gathering space hosting weekly farmers markets.", distance: "0.2 mi", distanceValue: 0.2, rating: 4.5, reviewCount: 98, imagePlaceholder: "person.3.fill", accentColor: .accentMint, isFeatured: false),
    ]

    // MARK: Daily Gem

    static let dailyGem = DailyGem(
        place: places[2],
        headline: "Spring Blooms at Botanica",
        reason: "The cherry blossoms are at peak bloom this week — a must-visit."
    )

    // MARK: Events (primary points source)

    static let events: [Event] = [
        Event(id: "river-cleanup-day", title: "River Cleanup Day", organizer: "Green Community Alliance", date: Calendar.current.date(byAdding: .day, value: 2, to: .now)!, time: "9:00 AM – 12:00 PM", locationName: "Riverside Park", attendeeCount: 34, maxAttendees: 50, category: .cleanup, imagePlaceholder: "sparkles", pointValue: 200),
        Event(id: "sunset-yoga", title: "Sunset Yoga in the Park", organizer: "Mindful Movement Co.", date: Calendar.current.date(byAdding: .day, value: 3, to: .now)!, time: "6:30 PM – 7:30 PM", locationName: "Overlook Bluff", attendeeCount: 18, maxAttendees: 30, category: .social, imagePlaceholder: "figure.yoga", pointValue: 100),
        Event(id: "weekend-farmers-market", title: "Weekend Farmers Market", organizer: "Local Growers Collective", date: Calendar.current.date(byAdding: .day, value: 5, to: .now)!, time: "8:00 AM – 1:00 PM", locationName: "The Commons", attendeeCount: 120, maxAttendees: nil, category: .market, imagePlaceholder: "bag.fill", pointValue: 75),
        Event(id: "youth-basketball", title: "Youth Basketball Tournament", organizer: "Parks & Rec Dept.", date: Calendar.current.date(byAdding: .day, value: 4, to: .now)!, time: "10:00 AM – 4:00 PM", locationName: "Cedar Court Complex", attendeeCount: 48, maxAttendees: 64, category: .sports, imagePlaceholder: "figure.basketball", pointValue: 150),
        Event(id: "nature-photo-walk", title: "Nature Photography Walk", organizer: "Shutter Club", date: Calendar.current.date(byAdding: .day, value: 6, to: .now)!, time: "7:00 AM – 9:00 AM", locationName: "Hawk Ridge Trail", attendeeCount: 12, maxAttendees: 20, category: .workshop, imagePlaceholder: "camera.fill", pointValue: 150),
        Event(id: "spring-festival", title: "Spring Community Festival", organizer: "City of Maplewood", date: Calendar.current.date(byAdding: .day, value: 8, to: .now)!, time: "11:00 AM – 8:00 PM", locationName: "Riverside Park", attendeeCount: 230, maxAttendees: nil, category: .festival, imagePlaceholder: "party.popper.fill", pointValue: 250),
    ]

    // MARK: Challenges

    static let challenges: [Challenge] = [
        Challenge(title: "Event Regular", description: "Attend 3 events this month", xpReward: 300, progress: 0.33, icon: "calendar.badge.checkmark", daysRemaining: 12),
        Challenge(title: "Community Hero", description: "Attend 2 cleanup events", xpReward: 250, progress: 0.5, icon: "heart.fill", daysRemaining: 18),
        Challenge(title: "Social Butterfly", description: "Attend 5 social events", xpReward: 400, progress: 0.2, icon: "person.2.fill", daysRemaining: 25),
        Challenge(title: "Park Explorer", description: "Visit 5 different parks", xpReward: 150, progress: 0.6, icon: "leaf.fill", daysRemaining: 9),
    ]

    // MARK: Community Posts

    static let communityPosts: [CommunityPost] = [
        CommunityPost(authorName: "Maya Chen", authorInitials: "MC", placeName: "Botanica Gardens", content: "The new butterfly pavilion is incredible! Spent two hours just watching them. Highly recommend visiting in the morning when it's quieter.", timeAgo: "2h ago", likeCount: 24, commentCount: 6, imagePlaceholder: "photo.fill"),
        CommunityPost(authorName: "Jordan Ellis", authorInitials: "JE", placeName: "Hawk Ridge Trail", content: "Finally completed the full loop! The summit view is worth every step. Pro tip: bring extra water, the last section is steep.", timeAgo: "5h ago", likeCount: 41, commentCount: 12, imagePlaceholder: "photo.fill"),
        CommunityPost(authorName: "Priya Sharma", authorInitials: "PS", placeName: "The Commons", content: "Farmers market haul was amazing today. Fresh strawberries, homemade bread, and the best lavender honey I've ever tasted.", timeAgo: "8h ago", likeCount: 33, commentCount: 8, imagePlaceholder: nil),
        CommunityPost(authorName: "Alex Rivera", authorInitials: "AR", placeName: "Marina Point", content: "Sunset kayaking session was absolutely magical tonight. The water was like glass. This is what Connectify is all about!", timeAgo: "1d ago", likeCount: 56, commentCount: 15, imagePlaceholder: "photo.fill"),
    ]

    // MARK: User Profile

    static let currentUser = UserProfile(
        name: "You",
        initials: "ME",
        joinDate: "March 2026",
        placesVisited: 12,
        totalXP: 1_850,
        currentStreak: 7,
        badges: [
            Badge(name: "First Steps", icon: "shoe.fill", earned: true),
            Badge(name: "Explorer", icon: "binoculars.fill", earned: true),
            Badge(name: "Social Butterfly", icon: "person.2.fill", earned: true),
            Badge(name: "Trailblazer", icon: "map.fill", earned: false),
            Badge(name: "Event Regular", icon: "calendar.badge.checkmark", earned: false),
            Badge(name: "Legend", icon: "crown.fill", earned: false),
        ]
    )

    // MARK: - Collectible Places

    /// Default center (Minneapolis) used before GPS lock
    static let defaultCenter = CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650)

    /// Generates collectible places around a center coordinate.
    static func collectiblePlaces(around center: CLLocationCoordinate2D) -> [CollectiblePlace] {
        let offsets: [(Double, Double)] = [
            ( 0.003,  0.004),   // Riverside Park — very close
            ( 0.015, -0.008),   // Hawk Ridge Trail — moderate
            (-0.006,  0.010),   // Botanica Gardens — close
            ( 0.005, -0.005),   // Lakeshore Playground — close
            (-0.020,  0.018),   // Marina Point — far
            ( 0.008,  0.002),   // Cedar Court Complex — close
            ( 0.025, -0.022),   // Overlook Bluff — far (legendary!)
            (-0.002, -0.003),   // The Commons — very close
        ]

        return zip(places, offsets).map { place, offset in
            CollectiblePlace(
                id: place.name.lowercased().replacingOccurrences(of: " ", with: "-"),
                place: place,
                rarity: CollectiblePlace.rarityFor(place.category),
                coordinate: CLLocationCoordinate2D(
                    latitude: center.latitude + offset.0,
                    longitude: center.longitude + offset.1
                )
            )
        }
    }

    /// Convenience: places around the default center (fallback before GPS)
    static let collectiblePlaces: [CollectiblePlace] = collectiblePlaces(around: defaultCenter)

    /// Find the CollectiblePlace wrapper for a given Place
    static func collectible(for place: Place, in list: [CollectiblePlace]? = nil) -> CollectiblePlace? {
        let source = list ?? collectiblePlaces
        return source.first { $0.place.id == place.id }
    }

    // MARK: - Rewards (rebalanced — requires sustained event attendance)

    static let rewards: [Reward] = [
        // Bronze tier (1000 pts — ~7-10 events)
        Reward(id: "starbucks-5", name: "$5 Starbucks", brand: "Starbucks", icon: "cup.and.saucer.fill", pointCost: 1000, tier: .bronze),
        Reward(id: "dunkin-5", name: "$5 Dunkin'", brand: "Dunkin'", icon: "mug.fill", pointCost: 1000, tier: .bronze),
        // Silver tier (2500 pts — ~17-25 events)
        Reward(id: "amazon-10", name: "$10 Amazon", brand: "Amazon", icon: "shippingbox.fill", pointCost: 2500, tier: .silver),
        Reward(id: "target-10", name: "$10 Target", brand: "Target", icon: "cart.fill", pointCost: 2500, tier: .silver),
        Reward(id: "chipotle-10", name: "$10 Chipotle", brand: "Chipotle", icon: "fork.knife", pointCost: 2500, tier: .silver),
        // Gold tier (7500 pts — ~40-50 events)
        Reward(id: "amazon-25", name: "$25 Amazon", brand: "Amazon", icon: "shippingbox.fill", pointCost: 7500, tier: .gold),
        Reward(id: "nike-25", name: "$25 Nike", brand: "Nike", icon: "shoe.fill", pointCost: 7500, tier: .gold),
        // Platinum tier (20000 pts — ~100+ events)
        Reward(id: "apple-50", name: "$50 Apple", brand: "Apple", icon: "apple.logo", pointCost: 20000, tier: .platinum),
        Reward(id: "rei-50", name: "$50 REI", brand: "REI", icon: "tent.fill", pointCost: 20000, tier: .platinum),
    ]
}
