import Foundation
import Observation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFunctions

// MARK: - Social Service (follows · Going · invites · friends-going · organizer)
//
// The client end of functions/src/social.ts and organizers.ts. Every WRITE goes
// through a callable — blocks are enforced and counts kept honest on the
// server, and the Firestore rules deny the client every direct write to these
// subcollections. What lives here is the local mirror the UI binds to
// (following set, Going set, friends-going per event, the invite inbox, server
// notifications, the user's organizer profile) and thin async wrappers.

struct FriendSummary: Identifiable, Hashable, Codable {
    let uid: String
    let displayName: String
    var kind: String = "user"          // user | organizer
    var id: String { uid }
    var initials: String {
        displayName.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased().ifEmpty("VM")
    }
}

struct FriendsGoing: Equatable {
    let count: Int
    let friends: [FriendSummary]
    static let none = FriendsGoing(count: 0, friends: [])
}

struct EventInvite: Identifiable, Equatable {
    let id: String
    let eventId: String
    let eventTitle: String
    let eventDate: Date?
    let fromUid: String
    let fromName: String
    let message: String
    let status: String                 // pending | accepted | declined
    let createdAt: Date?
}

struct ServerNotification: Identifiable, Equatable {
    let id: String
    let kind: String                   // friend-rsvp | invite | invite-accepted | …
    let title: String
    let body: String
    let actorUid: String?
    let eventId: String?
    let inviteId: String?
    var read: Bool
    let createdAt: Date?
}

struct OrganizerProfile: Equatable {
    let id: String
    let displayName: String
    let category: String
    let description: String
    let website: String?
    let status: String                 // pending | approved | rejected | suspended
    let eventCount: Int
    let followerCount: Int

    var isApproved: Bool { status == "approved" }
    var canPublish: Bool { status == "pending" || status == "approved" }
    var statusLabel: String {
        switch status {
        case "approved": return "Verified organizer"
        case "pending": return "Under review"
        case "rejected": return "Not approved"
        case "suspended": return "Suspended"
        default: return status.capitalized
        }
    }
}

@MainActor @Observable
final class SocialService {

    // MARK: - State

    private(set) var followingIDs: Set<String> = []
    private(set) var friends: [FriendSummary] = []            // people I follow (kind == user)
    private(set) var followedOrganizerIDs: Set<String> = []
    private(set) var goingEventIDs: Set<String> = []
    private(set) var friendsGoingByEvent: [String: FriendsGoing] = [:]
    private(set) var invites: [EventInvite] = []
    private(set) var notifications: [ServerNotification] = []
    private(set) var organizer: OrganizerProfile? = nil
    private(set) var followerCount = 0
    private(set) var followingCount = 0
    var activityPrivacy: String = "friends"
    var lastError: String?

    var unreadNotificationCount: Int { notifications.filter { !$0.read }.count }
    var pendingInvites: [EventInvite] { invites.filter { $0.status == "pending" } }

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }
    private var friendsGoingFetchedAt: [String: Date] = [:]
    private let friendsGoingTTL: TimeInterval = 120

    // MARK: - Refresh

    /// Pull the user's social mirror: following, Going state, invites, notifications, organizer.
    func refreshAll() async {
        guard let uid else { clearLocal(); return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshFollowing(uid: uid) }
            group.addTask { await self.refreshUserDoc(uid: uid) }
            group.addTask { await self.refreshInvites(uid: uid) }
            group.addTask { await self.refreshNotifications(uid: uid) }
            group.addTask { await self.refreshOrganizer() }
        }
    }

    func clearLocal() {
        followingIDs = []; friends = []; followedOrganizerIDs = []; goingEventIDs = []
        friendsGoingByEvent = [:]; invites = []; notifications = []; organizer = nil
        followerCount = 0; followingCount = 0; activityPrivacy = "friends"
    }

    private func refreshFollowing(uid: String) async {
        do {
            let snap = try await db.collection("users").document(uid).collection("following").getDocuments()
            var ids = Set<String>(); var people: [FriendSummary] = []; var orgs = Set<String>()
            for d in snap.documents {
                ids.insert(d.documentID)
                let kind = (d.data()["kind"] as? String) ?? "user"
                let name = Sanitize.text(d.data()["displayName"] as? String, max: 60).ifEmpty("A Verdure member")
                if kind == "organizer" { orgs.insert(d.documentID) }
                else { people.append(FriendSummary(uid: d.documentID, displayName: name, kind: kind)) }
            }
            followingIDs = ids
            friends = people.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            followedOrganizerIDs = orgs
        } catch { lastError = error.localizedDescription }
    }

    private func refreshUserDoc(uid: String) async {
        do {
            let d = try await db.collection("users").document(uid).getDocument().data() ?? [:]
            goingEventIDs = Set((d["rsvpEventIDs"] as? [String]) ?? [])
            followerCount = d["followerCount"] as? Int ?? 0
            followingCount = d["followingCount"] as? Int ?? 0
            activityPrivacy = (d["activityPrivacy"] as? String) ?? "friends"
        } catch { lastError = error.localizedDescription }
    }

    private func refreshInvites(uid: String) async {
        do {
            let snap = try await db.collection("users").document(uid).collection("invites")
                .order(by: "createdAt", descending: true).limit(to: 50).getDocuments()
            invites = snap.documents.map { d in
                let x = d.data()
                return EventInvite(
                    id: d.documentID,
                    eventId: (x["eventId"] as? String) ?? "",
                    eventTitle: Sanitize.text(x["eventTitle"] as? String, max: 120).ifEmpty("An event"),
                    eventDate: (x["eventDate"] as? Timestamp)?.dateValue(),
                    fromUid: (x["fromUid"] as? String) ?? "",
                    fromName: Sanitize.text(x["fromName"] as? String, max: 60).ifEmpty("A friend"),
                    message: Sanitize.text(x["message"] as? String, max: 280),
                    status: (x["status"] as? String) ?? "pending",
                    createdAt: (x["createdAt"] as? Timestamp)?.dateValue())
            }
        } catch { lastError = error.localizedDescription }
    }

    private func refreshNotifications(uid: String) async {
        do {
            let snap = try await db.collection("users").document(uid).collection("notifications")
                .order(by: "createdAt", descending: true).limit(to: 50).getDocuments()
            notifications = snap.documents.map { d in
                let x = d.data()
                return ServerNotification(
                    id: d.documentID,
                    kind: (x["kind"] as? String) ?? "system",
                    title: Sanitize.text(x["title"] as? String, max: 120).ifEmpty("Verdure"),
                    body: Sanitize.text(x["body"] as? String, max: 300),
                    actorUid: x["actorUid"] as? String,
                    eventId: x["eventId"] as? String,
                    inviteId: x["inviteId"] as? String,
                    read: (x["read"] as? Bool) ?? false,
                    createdAt: (x["createdAt"] as? Timestamp)?.dateValue())
            }
        } catch { lastError = error.localizedDescription }
    }

    func refreshOrganizer() async {
        guard uid != nil else { organizer = nil; return }
        do {
            let data = try await Self.call("myOrganizer", [:])
            guard let o = data["organizer"] as? [String: Any], let id = o["id"] as? String else { organizer = nil; return }
            organizer = OrganizerProfile(
                id: id,
                displayName: Sanitize.text(o["displayName"] as? String, max: 80),
                category: (o["category"] as? String) ?? "other",
                description: Sanitize.text(o["description"] as? String, max: 600),
                website: Sanitize.url(o["website"] as? String),
                status: (o["status"] as? String) ?? "pending",
                eventCount: o["eventCount"] as? Int ?? 0,
                followerCount: o["followerCount"] as? Int ?? 0)
        } catch { /* leave as is */ }
    }

    // MARK: - Follows

    func isFollowing(_ id: String?) -> Bool { id.map { followingIDs.contains($0) } ?? false }

    @discardableResult
    func setFollowing(_ targetId: String, kind: String = "user", follow: Bool, displayName: String? = nil) async -> Bool {
        do {
            _ = try await Self.call("followUser", ["targetId": targetId, "kind": kind, "follow": follow])
            if follow {
                followingIDs.insert(targetId)
                if kind == "organizer" { followedOrganizerIDs.insert(targetId) }
                else if !friends.contains(where: { $0.uid == targetId }) {
                    friends.append(FriendSummary(uid: targetId, displayName: displayName ?? "A Verdure member", kind: kind))
                }
                followingCount += 1
            } else {
                followingIDs.remove(targetId); followedOrganizerIDs.remove(targetId)
                friends.removeAll { $0.uid == targetId }
                followingCount = max(0, followingCount - 1)
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Going / RSVP

    func isGoing(_ eventId: String) -> Bool { goingEventIDs.contains(eventId) }

    /// Mark Going / not going. Optimistic; reverts on failure and surfaces the server's reason.
    @discardableResult
    func setGoing(_ eventId: String, going: Bool) async -> Bool {
        let before = goingEventIDs
        if going { goingEventIDs.insert(eventId) } else { goingEventIDs.remove(eventId) }
        do {
            let data = try await Self.call("rsvpToEvent", ["eventId": eventId, "going": going])
            if let g = data["going"] as? Bool { if g { goingEventIDs.insert(eventId) } else { goingEventIDs.remove(eventId) } }
            invites = invites.map { inv in
                guard inv.eventId == eventId, inv.status == "pending", going else { return inv }
                return EventInvite(id: inv.id, eventId: inv.eventId, eventTitle: inv.eventTitle, eventDate: inv.eventDate,
                                   fromUid: inv.fromUid, fromName: inv.fromName, message: inv.message, status: "accepted", createdAt: inv.createdAt)
            }
            friendsGoingFetchedAt.removeValue(forKey: eventId)
            return true
        } catch {
            goingEventIDs = before
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Friends going

    func friendsGoing(for eventId: String) -> FriendsGoing { friendsGoingByEvent[eventId] ?? .none }

    /// Refresh friends-going for a set of events (batched, cached for 2 minutes).
    func loadFriendsGoing(for eventIds: [String], force: Bool = false) async {
        guard uid != nil else { return }
        let now = Date()
        let wanted = Array(Set(eventIds)).filter { id in
            force || (friendsGoingFetchedAt[id].map { now.timeIntervalSince($0) > friendsGoingTTL } ?? true)
        }.prefix(50)
        guard !wanted.isEmpty else { return }
        do {
            let data = try await Self.call("friendsGoing", ["eventIds": Array(wanted)])
            let events = (data["events"] as? [String: Any]) ?? [:]
            for id in wanted {
                let entry = events[id] as? [String: Any]
                let people = ((entry?["friends"] as? [[String: Any]]) ?? []).compactMap { f -> FriendSummary? in
                    guard let fuid = f["uid"] as? String else { return nil }
                    return FriendSummary(uid: fuid, displayName: Sanitize.text(f["displayName"] as? String, max: 60).ifEmpty("A friend"))
                }
                friendsGoingByEvent[id] = FriendsGoing(count: entry?["count"] as? Int ?? people.count, friends: people)
                friendsGoingFetchedAt[id] = now
            }
        } catch { lastError = error.localizedDescription }
    }

    // MARK: - Invites

    /// Returns the uids the server actually delivered to.
    func invite(eventId: String, to uids: [String], message: String) async -> [String] {
        do {
            let data = try await Self.call("inviteToEvent", ["eventId": eventId, "toUids": uids,
                                                              "message": String(message.prefix(280))])
            return (data["delivered"] as? [String]) ?? []
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func declineInvite(_ inviteId: String) async {
        do {
            _ = try await Self.call("respondToInvite", ["inviteId": inviteId])
            invites = invites.map { inv in
                guard inv.id == inviteId else { return inv }
                return EventInvite(id: inv.id, eventId: inv.eventId, eventTitle: inv.eventTitle, eventDate: inv.eventDate,
                                   fromUid: inv.fromUid, fromName: inv.fromName, message: inv.message, status: "declined", createdAt: inv.createdAt)
            }
        } catch { lastError = error.localizedDescription }
    }

    // MARK: - Notifications

    func markNotificationRead(_ id: String) async {
        guard let uid else { return }
        if let i = notifications.firstIndex(where: { $0.id == id }) { notifications[i].read = true }
        try? await db.collection("users").document(uid).collection("notifications").document(id).updateData(["read": true])
    }

    func markAllNotificationsRead() async {
        for n in notifications where !n.read { await markNotificationRead(n.id) }
    }

    // MARK: - Privacy

    func setActivityPrivacy(_ value: String) async {
        guard let uid, value == "friends" || value == "public" else { return }
        activityPrivacy = value
        try? await db.collection("users").document(uid).setData(["activityPrivacy": value], merge: true)
    }

    // MARK: - Organizer

    /// Apply for an organizer profile. Returns the status ("pending" on success).
    func createOrganizer(displayName: String, category: String, description: String, website: String) async -> String? {
        do {
            let payload: [String: any Sendable] = ["displayName": displayName, "category": category,
                                                   "description": description, "website": website]
            let data = try await Self.call("createOrganizer", payload)
            await refreshOrganizer()
            return data["status"] as? String
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Publish an event as the organizer. Returns (eventId, broadcast) or nil.
    func createEvent(title: String, description: String, locationName: String, time: String,
                     start: Date, category: EventCategory, maxAttendees: Int?, isFree: Bool,
                     latitude: Double?, longitude: Double?, website: String?) async -> (id: String, broadcast: Bool)? {
        var payload: [String: any Sendable] = [
            "title": title, "description": description, "locationName": locationName, "time": time,
            "startMs": Int(start.timeIntervalSince1970 * 1000), "category": category.rawValue, "isFree": isFree,
        ]
        if let maxAttendees { payload["maxAttendees"] = maxAttendees }
        if let latitude, let longitude { payload["latitude"] = latitude; payload["longitude"] = longitude }
        if let website, !website.isEmpty { payload["website"] = website }
        do {
            let data = try await Self.call("createEvent", payload)
            guard let id = data["eventId"] as? String else { return nil }
            await refreshOrganizer()
            return (id, data["broadcast"] as? Bool ?? false)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Plumbing

    private static func call(_ name: String, _ payload: [String: any Sendable]) async throws -> [String: Any] {
        do {
            let result = try await Functions.functions().httpsCallable(name).call(payload)
            return result.data as? [String: Any] ?? [:]
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain, FunctionsErrorCode(rawValue: error.code) == .unauthenticated {
                throw ServerCallError.notSignedIn
            }
            if error.domain == NSURLErrorDomain { throw ServerCallError.offline }
            throw ServerCallError.server(error.localizedDescription)
        }
    }
}
