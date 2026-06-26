import Foundation
import SwiftUI
import Observation
import UserNotifications

// MARK: - In-app notification model

struct AppNotification: Identifiable {
    enum Kind {
        case event, badge, points, community, gem, system
        var icon: String {
            switch self {
            case .event: return "calendar.badge.clock"
            case .badge: return "rosette"
            case .points: return "sparkles"
            case .community: return "bubble.left.and.bubble.right.fill"
            case .gem: return "diamond.fill"
            case .system: return "leaf.fill"
            }
        }
        var kind: ClayStyle.ClayAccentKind {
            switch self {
            case .event: return .spruce
            case .badge: return .gold
            case .points: return .gold
            case .community: return .teal
            case .gem: return .terracotta
            case .system: return .spruce
            }
        }
    }
    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    let timeAgo: String
    var isRead: Bool = false
}

// MARK: - Notification manager (local notifications + in-app inbox)

@MainActor @Observable
final class NotificationManager {
    static let shared = NotificationManager()

    var inbox: [AppNotification] = []
    var permissionGranted = false
    /// User-facing on/off (in Settings). Local reminders are only scheduled when enabled.
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "notificationsEnabled") }
    }

    var unreadCount: Int { inbox.filter { !$0.isRead }.count }

    private init() {
        self.enabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        seedInbox()
        refreshPermissionStatus()
    }

    // MARK: Permission

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        permissionGranted = granted
    }

    func refreshPermissionStatus() {
        // Read the status off-actor (UNNotificationSettings isn't Sendable, and the
        // completion fires on a background queue), then hop back with just a Bool.
        Task.detached {
            let granted = await Self.currentAuthorization()
            await MainActor.run { Self.shared.permissionGranted = granted }
        }
    }

    nonisolated private static func currentAuthorization() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                cont.resume(returning: settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional)
            }
        }
    }

    // MARK: Inbox

    func markAllRead() {
        inbox = inbox.map { var n = $0; n.isRead = true; return n }
    }

    func push(_ notification: AppNotification) {
        inbox.insert(notification, at: 0)
    }

    // MARK: Local notifications

    /// Schedule a reminder the day before an event (or shortly out if it's near),
    /// and drop an entry into the in-app inbox.
    func scheduleEventReminder(for event: Event) {
        push(AppNotification(kind: .event, title: "Reminder set",
                             message: "We'll remind you before “\(event.title)”.", timeAgo: "now"))
        guard enabled, permissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming: \(event.title)"
        content.body = "\(event.time) · \(event.locationName)"
        content.sound = .default

        let cal = Calendar.current
        let dayBefore = cal.date(byAdding: .day, value: -1, to: event.date) ?? event.date
        let trigger: UNNotificationTrigger
        if dayBefore > Date() {
            var comps = cal.dateComponents([.year, .month, .day], from: dayBefore)
            comps.hour = 9
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            // Event is imminent/past — fire a short confirmation instead.
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        }
        let request = UNNotificationRequest(identifier: "event-\(event.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelEventReminder(for event: Event) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["event-\(event.id)"])
    }

    // MARK: Seed (realistic inbox for first run / demo)

    private func seedInbox() {
        inbox = [
            AppNotification(kind: .gem, title: "Today's Daily Gem is ready",
                            message: "Tap the gem to reveal a new fact about your neighborhood.", timeAgo: "2m"),
            AppNotification(kind: .badge, title: "Badge unlocked: Social Butterfly",
                            message: "You've attended 3 community events. Nice!", timeAgo: "3h"),
            AppNotification(kind: .event, title: "Event tomorrow",
                            message: "River Cleanup Day starts at 9:00 AM at Riverside Park.", timeAgo: "5h"),
            AppNotification(kind: .points, title: "+200 points earned",
                            message: "Thanks for checking in to Weekend Farmers Market.", timeAgo: "1d", isRead: true),
            AppNotification(kind: .community, title: "Maya mentioned a spot you collected",
                            message: "“The butterfly pavilion at Botanica Gardens is incredible!”", timeAgo: "1d", isRead: true),
        ]
    }
}
