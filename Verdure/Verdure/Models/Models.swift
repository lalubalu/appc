import Foundation
import SwiftUI

// MARK: - Place

struct Place: Identifiable, Hashable {
    let id: String              // Stable string ID (OSM node ID or sample slug)
    let name: String
    let category: PlaceCategory
    let shortDescription: String
    let distance: String        // e.g. "0.4 mi"
    let distanceValue: Double   // numeric miles for proximity checks
    let rating: Double
    let reviewCount: Int
    let imagePlaceholder: String // SF Symbol name
    let accentColor: Color
    let isFeatured: Bool

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id }
}

enum PlaceCategory: String, CaseIterable, Identifiable {
    case parks = "Parks"
    case trails = "Trails"
    case gardens = "Gardens"
    case playgrounds = "Playgrounds"
    case waterfront = "Waterfront"
    case sports = "Sports"
    case scenic = "Scenic"
    case community = "Community"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .parks: return "leaf.fill"
        case .trails: return "figure.hiking"
        case .gardens: return "camera.macro"
        case .playgrounds: return "figure.play"
        case .waterfront: return "water.waves"
        case .sports: return "sportscourt.fill"
        case .scenic: return "mountain.2.fill"
        case .community: return "person.3.fill"
        }
    }

    var tint: Color {
        switch self {
        case .parks: return .verdureGreen
        case .trails: return .accentAmber
        case .gardens: return .accentCoral
        case .playgrounds: return .accentSky
        case .waterfront: return .accentSky
        case .sports: return .accentCoral
        case .scenic: return .accentLavender
        case .community: return .accentMint
        }
    }
}

// MARK: - Event

struct Event: Identifiable, Hashable {
    let id: String               // stable ID for persistence
    let title: String
    let organizer: String
    let date: Date
    let time: String
    let locationName: String
    let attendeeCount: Int
    let maxAttendees: Int?
    let category: EventCategory
    let imagePlaceholder: String
    let pointValue: Int          // points earned for attending
    var description: String?     // optional event description
    var creatorID: String?       // Firebase UID of the event creator

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Event, rhs: Event) -> Bool { lhs.id == rhs.id }
}

enum EventCategory: String, CaseIterable, Identifiable, Codable {
    case cleanup = "Cleanup"
    case sports = "Sports"
    case social = "Social"
    case workshop = "Workshop"
    case market = "Market"
    case festival = "Festival"
    case hackathon = "Hackathon"
    case meetup = "Meetup"
    case volunteer = "Volunteer"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cleanup: return "sparkles"
        case .sports: return "figure.run"
        case .social: return "cup.and.saucer.fill"
        case .workshop: return "hammer.fill"
        case .market: return "bag.fill"
        case .festival: return "party.popper.fill"
        case .hackathon: return "laptopcomputer"
        case .meetup: return "person.3.fill"
        case .volunteer: return "heart.fill"
        }
    }

    /// Points earned for attending events of this category
    var defaultPoints: Int {
        switch self {
        case .cleanup: return 200
        case .sports: return 150
        case .social: return 100
        case .workshop: return 150
        case .market: return 75
        case .festival: return 250
        case .hackathon: return 200
        case .meetup: return 100
        case .volunteer: return 200
        }
    }
}

// MARK: - Daily Gem

struct DailyGem: Identifiable {
    let id = UUID()
    let place: Place
    let headline: String
    let reason: String
}

// MARK: - Challenge

struct Challenge: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let xpReward: Int
    let progress: Double   // 0.0 – 1.0
    let icon: String
    let daysRemaining: Int
}

// MARK: - Community Post

struct CommunityPost: Identifiable {
    let id = UUID()
    let authorName: String
    let authorInitials: String
    let placeName: String
    let content: String
    let timeAgo: String
    let likeCount: Int
    let commentCount: Int
    let imagePlaceholder: String?
}

// MARK: - User Profile

struct UserProfile {
    let name: String
    let initials: String
    let joinDate: String
    let placesVisited: Int
    let totalXP: Int
    let currentStreak: Int
    let badges: [Badge]
}

struct Badge: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let earned: Bool
}
