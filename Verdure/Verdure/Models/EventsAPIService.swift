import Foundation
import CoreLocation
import SwiftUI
import Observation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFunctions

// MARK: - Events Service (Firestore only)
//
// INGEST-AND-OWN. Events are fetched from every source (Ticketmaster, library
// and civic calendars, Localist, NPS, SerpApi as a gap-filler, organizer
// accounts) by scheduled Cloud Functions, deduplicated once at write time and
// stored in the normalized /events collection. This class READS THAT
// COLLECTION AND NOTHING ELSE: no user request ever triggers an upstream API
// call, no vendor key ships in the app, and the same corpus powers push,
// personalisation and the planner.
//
// The previous model (SerpApi + five client-side providers fanned out on every
// open) could do none of that and burned the 100-search monthly quota on the
// first few users. It is gone, not disabled — see functions/src/ingest/.
@MainActor @Observable
final class EventsAPIService {

    // MARK: - Published State

    var events: [Event] = []
    var isLoading = false
    var lastError: String? = nil
    /// Set when the user is outside every launch area — the honest reason the
    /// list may be empty or far away. Nil inside a covered area.
    var coverageNotice: String? = nil
    /// The launch area the user is in (or nearest to).
    var activeArea: LaunchArea? = nil
    private(set) var launchAreas: [LaunchArea] = LaunchArea.builtIn

    // MARK: - Private

    private var db: Firestore { Firestore.firestore() }
    private var followedOrganizerIDs: Set<String> = []
    private var lastFetchDate: Date?
    private var cachedCenter: CLLocationCoordinate2D?
    /// Firestore reads are cheap and the store changes hourly; refresh gently.
    private let fetchCooldown: TimeInterval = 300
    /// The whole upcoming corpus for a launch area comfortably fits; filtering
    /// (radius, category, free/paid, search) happens locally with no network.
    private let maxEvents = 600

    // Cache
    private let cacheKey = "cachedEventsJSON.v2"
    private let cacheCenterKey = "cachedEventsCenter.v2"
    private let cacheTimestampKey = "cachedEventsTimestamp.v2"
    private let cacheTTL: TimeInterval = 6 * 3600

    // MARK: - Init

    init() {
        loadCachedEvents()
        if events.isEmpty { useSampleFallback() }
    }

    // MARK: - Public API

    /// Load upcoming events from the normalized store. `center` is used only
    /// for the coverage notice — the query itself is not geographic, because
    /// ingestion is already scoped to launch areas.
    func fetchNearbyEvents(around center: CLLocationCoordinate2D, followedOrganizerIDs: Set<String> = []) async {
        if QAData.offline { return }   // QA: cached/sample data only
        updateCoverage(for: center)
        // Remember the follow set across plain refreshes (which pass none).
        if !followedOrganizerIDs.isEmpty { self.followedOrganizerIDs = followedOrganizerIDs }
        if let cached = cachedCenter, let last = lastFetchDate,
           Date().timeIntervalSince(last) < fetchCooldown,
           distance(cached, center) < 5000 {
            return
        }

        // Unstructured so it survives view-lifecycle churn at launch.
        await Task { @MainActor in
            self.isLoading = true
            self.lastError = nil
            if let fetched = await self.fetchFirestoreEvents() {
                // Followed organizers who aren't approved yet are visible only to
                // their followers — a separate, rules-permitted query per organizer.
                let followerOnly = await self.fetchFollowedOrganizerEvents(self.followedOrganizerIDs)
                var merged = fetched
                let seen = Set(fetched.map(\.id))
                merged.append(contentsOf: followerOnly.filter { !seen.contains($0.id) })
                // A successful read is the truth — including an honest empty list.
                self.events = merged.sorted { $0.date < $1.date }
                self.cachedCenter = center
                self.persistCache(center: center)
            }
            // nil = the read failed (offline / rules / no auth); keep what we had.
            self.lastFetchDate = Date()
            self.isLoading = false
        }.value
    }

    /// Force refresh, ignoring cooldown.
    /// Look up a single event by id — the shape a notification deep link
    /// arrives in. Checks what's already loaded first, then Firestore, because
    /// a tap that lands on a cached event should be instant and offline-safe.
    /// Returns nil when the event is genuinely gone (cancelled, hidden by
    /// moderation, or aged out between the push and the tap), which the caller
    /// must show honestly rather than as an empty screen.
    func event(withID id: String) async -> Event? {
        if let local = events.first(where: { $0.id == id }) { return local }
        do {
            let doc = try await Firestore.firestore().collection("events").document(id).getDocument()
            guard doc.exists else { return nil }
            return Self.mapFirestoreDocument(doc)
        } catch {
            print("[EventsAPI] event(withID:) failed: \(error.localizedDescription)")
            return nil
        }
    }

    func refresh(around center: CLLocationCoordinate2D) async {
        lastFetchDate = nil
        cachedCenter = nil
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        await fetchNearbyEvents(around: center)
    }

    /// Refresh the launch-area list from the server (cheap; falls back to the mirror).
    func refreshLaunchAreas() async {
        do {
            let result = try await Functions.functions().httpsCallable("listLaunchAreas").call([:])
            guard let data = result.data as? [String: Any],
                  let raw = data["areas"] as? [[String: Any]] else { return }
            let parsed: [LaunchArea] = raw.compactMap { a in
                guard let id = a["id"] as? String, let name = a["name"] as? String,
                      let center = a["center"] as? [String: Any],
                      let lat = Sanitize.coord(center["lat"]), let lng = Sanitize.coord(center["lng"]),
                      let radius = Sanitize.coord(a["radiusMiles"]) else { return nil }
                return LaunchArea(id: id, name: Sanitize.text(name, max: 60), latitude: lat, longitude: lng, radiusMiles: radius)
            }
            if !parsed.isEmpty { launchAreas = parsed }
        } catch {
            // The built-in mirror is fine; this is a courtesy refresh.
        }
    }

    /// Create a community event (server-owned visibility flags are set by rules/functions).
    func createEvent(
        title: String,
        description: String,
        organizer: String,
        date: Date,
        time: String,
        locationName: String,
        maxAttendees: Int?,
        category: EventCategory
    ) async -> Event? {
        guard let currentUser = Auth.auth().currentUser else {
            lastError = "You must be signed in to create an event."
            return nil
        }

        let eventID = UUID().uuidString
        let pointValue = category.defaultPoints

        // Best-effort forward geocode of the venue so the server can verify
        // attendee proximity at check-in. Failure is non-fatal (event still posts).
        let venueCoordinate = await Self.geocode(locationName)

        var data: [String: Any] = [
            "title": sanitize(title, max: 200),
            "description": sanitize(description, max: 2000),
            "organizer": sanitize(organizer, max: 200),
            "date": Timestamp(date: date),
            "time": sanitize(time, max: 50),
            "locationName": sanitize(locationName, max: 300),
            "attendeeCount": 1,
            "maxAttendees": maxAttendees as Any,
            "category": category.rawValue,
            "imagePlaceholder": category.icon,
            "pointValue": pointValue,
            "creatorID": currentUser.uid,
            "createdAt": FieldValue.serverTimestamp(),
            // Moderation + store flags — required on create by the rules, server-owned after.
            "hidden": false,
            "active": true,
            "source": "community",
        ]
        if let venueCoordinate {
            data["latitude"] = venueCoordinate.latitude
            data["longitude"] = venueCoordinate.longitude
        }

        do {
            try await db.collection("events").document(eventID).setData(data)
            let event = Event(
                id: eventID, title: title, organizer: organizer, date: date, time: time,
                locationName: locationName, attendeeCount: 1, maxAttendees: maxAttendees,
                category: category, imagePlaceholder: category.icon, pointValue: pointValue,
                description: description, creatorID: currentUser.uid,
                latitude: venueCoordinate?.latitude, longitude: venueCoordinate?.longitude,
                source: "community", isFree: true)
            events.insert(event, at: 0)
            events.sort { $0.date < $1.date }
            return event
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Delete an event (only if current user is the creator).
    func deleteEvent(_ eventID: String) async -> Bool {
        guard let currentUser = Auth.auth().currentUser else { return false }
        guard let event = events.first(where: { $0.id == eventID }),
              event.creatorID == currentUser.uid else {
            lastError = "You can only delete events you created."
            return false
        }
        do {
            try await db.collection("events").document(eventID).delete()
            events.removeAll { $0.id == eventID }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Firestore

    /// The app's ONLY event query. Every clause is required by the read rules
    /// ("rules are not filters"): hidden == false, and either broadcast == true
    /// (public listings — readable signed out) or the caller follows the organizer.
    /// Returns nil when the read fails so callers keep their cache.
    private func fetchFirestoreEvents() async -> [Event]? {
        do {
            let now = Timestamp(date: Date().addingTimeInterval(-3600))
            let snapshot = try await db.collection("events")
                .whereField("hidden", isEqualTo: false)
                .whereField("active", isEqualTo: true)
                .whereField("broadcast", isEqualTo: true)
                .whereField("date", isGreaterThanOrEqualTo: now)
                .order(by: "date")
                .limit(to: maxEvents)
                .getDocuments()
            return snapshot.documents.compactMap { Self.mapFirestoreDocument($0) }
        } catch {
            lastError = "Couldn't reach the event store. Showing what was saved on this device."
            print("[EventsAPI] Firestore error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Events from organizers the user follows that are NOT yet broadcast. The
    /// rules allow this read only when the query pins organizerId, which is why
    /// it is one query per followed organizer (bounded to 20).
    private func fetchFollowedOrganizerEvents(_ organizerIDs: Set<String>) async -> [Event] {
        guard Auth.auth().currentUser != nil, !organizerIDs.isEmpty else { return [] }
        var out: [Event] = []
        let cutoff = Timestamp(date: Date().addingTimeInterval(-3600))
        for orgId in organizerIDs.prefix(20) {
            do {
                let snap = try await db.collection("events")
                    .whereField("hidden", isEqualTo: false)
                    .whereField("active", isEqualTo: true)
                    .whereField("organizerId", isEqualTo: orgId)
                    .whereField("date", isGreaterThanOrEqualTo: cutoff)
                    .limit(to: 100)
                    .getDocuments()
                out.append(contentsOf: snap.documents.compactMap { Self.mapFirestoreDocument($0) })
            } catch {
                print("[EventsAPI] organizer \(orgId) query failed: \(error.localizedDescription)")
            }
        }
        return out
    }

    /// Community events are user-generated and ingested events came from third
    /// parties — both are scrubbed on read like any other external data.
    static func mapFirestoreDocument(_ doc: DocumentSnapshot) -> Event? {
        guard let data = doc.data() else { return nil }
        guard let title = data["title"] as? String,
              let organizer = data["organizer"] as? String,
              let timestamp = data["date"] as? Timestamp,
              let time = data["time"] as? String,
              let locationName = data["locationName"] as? String,
              let categoryRaw = data["category"] as? String else {
            return nil
        }
        let category = EventCategory(rawValue: categoryRaw) ?? .social
        let safeDescription = Sanitize.text(data["description"] as? String, max: 600)
        let tags = ((data["tags"] as? [String]) ?? []).map { Sanitize.text($0, max: 40) }.filter { !$0.isEmpty }
        let sources = (data["sources"] as? [[String: Any]]) ?? []
        let priceMin = Sanitize.coord(data["priceMin"])
        return Event(
            id: doc.documentID,
            title: Sanitize.text(title, max: 120).ifEmpty("Untitled event"),
            organizer: Sanitize.text(organizer, max: 80).ifEmpty("Community"),
            date: timestamp.dateValue(),
            time: Sanitize.text(time, max: 60).ifEmpty("Time TBA"),
            locationName: Sanitize.text(locationName, max: 100).ifEmpty("Location TBA"),
            attendeeCount: data["attendeeCount"] as? Int ?? 0,
            maxAttendees: data["maxAttendees"] as? Int,
            category: category,
            imagePlaceholder: category.icon,   // never trust a remote SF Symbol name
            pointValue: min(data["pointValue"] as? Int ?? category.defaultPoints, category.defaultPoints),
            description: safeDescription.isEmpty ? nil : safeDescription,
            creatorID: data["creatorID"] as? String,
            website: Sanitize.url(data["website"] as? String),
            latitude: Sanitize.latitude(Sanitize.coord(data["latitude"])),
            longitude: Sanitize.longitude(Sanitize.coord(data["longitude"])),
            source: (data["source"] as? String).map { Sanitize.text($0, max: 30) } ?? "community",
            sourceCount: max(1, sources.count),
            isFree: data["isFree"] as? Bool,
            priceMin: priceMin,
            imageURL: Sanitize.url(data["imageURL"] as? String),
            tags: tags,
            areaId: data["areaId"] as? String,
            organizerId: data["organizerId"] as? String,
            isBroadcast: (data["broadcast"] as? Bool) ?? true
        )
    }

    /// Forward-geocode a venue string to a coordinate (best-effort, nil on failure).
    static func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.geocodeAddressString(trimmed)
        return placemarks?.first?.location?.coordinate
    }

    // MARK: - Coverage

    private func updateCoverage(for center: CLLocationCoordinate2D) {
        guard let nearest = LaunchArea.nearest(to: center, in: launchAreas) else { return }
        activeArea = nearest
        if nearest.covers(center) {
            coverageNotice = nil
        } else {
            let miles = Int(nearest.distanceMiles(from: center).rounded())
            coverageNotice = "Verdure hasn't launched where you are yet. Showing \(nearest.name), \(miles) miles away."
        }
    }

    // MARK: - Cache

    private func persistCache(center: CLLocationCoordinate2D) {
        let encodable = events.map { CachedEvent(from: $0) }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        UserDefaults.standard.set([center.latitude, center.longitude], forKey: cacheCenterKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
    }

    private func loadCachedEvents() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CachedEvent].self, from: data),
              let centerArr = UserDefaults.standard.array(forKey: cacheCenterKey) as? [Double],
              centerArr.count == 2,
              isCacheValid() else { return }
        cachedCenter = CLLocationCoordinate2D(latitude: centerArr[0], longitude: centerArr[1])
        // Drop anything that has already happened.
        let cutoff = Date().addingTimeInterval(-3600)
        events = cached.map { $0.toEvent() }.filter { $0.date >= cutoff }
    }

    private func isCacheValid() -> Bool {
        let ts = UserDefaults.standard.double(forKey: cacheTimestampKey)
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < cacheTTL
    }

    // MARK: - Helpers

    /// QA harness only (DEBUG + `-QAOfflineData YES`). In every other build this
    /// is a no-op and the screens render their honest empty states.
    private func useSampleFallback() {
        guard SampleData.isEnabled else { return }
        events = SampleData.events
    }

    private func sanitize(_ input: String, max: Int) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(max))
    }

    private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

// MARK: - Cache Model

private struct CachedEvent: Codable {
    let id: String
    let title: String
    let organizer: String
    let dateInterval: TimeInterval
    let time: String
    let locationName: String
    let attendeeCount: Int
    let maxAttendees: Int?
    let categoryRaw: String
    let imagePlaceholder: String
    let pointValue: Int
    let description: String?
    let creatorID: String?
    let website: String?
    let latitude: Double?
    let longitude: Double?
    let source: String?
    let sourceCount: Int?
    let isFree: Bool?
    let priceMin: Double?
    let imageURL: String?
    let tags: [String]?
    let areaId: String?
    let organizerId: String?
    let isBroadcast: Bool?

    init(from event: Event) {
        id = event.id; title = event.title; organizer = event.organizer
        dateInterval = event.date.timeIntervalSince1970; time = event.time
        locationName = event.locationName; attendeeCount = event.attendeeCount
        maxAttendees = event.maxAttendees; categoryRaw = event.category.rawValue
        imagePlaceholder = event.imagePlaceholder; pointValue = event.pointValue
        description = event.description; creatorID = event.creatorID; website = event.website
        latitude = event.latitude; longitude = event.longitude
        source = event.source; sourceCount = event.sourceCount; isFree = event.isFree
        priceMin = event.priceMin; imageURL = event.imageURL; tags = event.tags
        areaId = event.areaId; organizerId = event.organizerId; isBroadcast = event.isBroadcast
    }

    func toEvent() -> Event {
        let category = EventCategory(rawValue: categoryRaw) ?? .social
        return Event(
            id: id, title: title, organizer: organizer,
            date: Date(timeIntervalSince1970: dateInterval), time: time,
            locationName: locationName, attendeeCount: attendeeCount, maxAttendees: maxAttendees,
            category: category, imagePlaceholder: imagePlaceholder, pointValue: pointValue,
            description: description, creatorID: creatorID, website: website,
            latitude: latitude, longitude: longitude,
            source: source ?? "community", sourceCount: sourceCount ?? 1, isFree: isFree,
            priceMin: priceMin, imageURL: imageURL, tags: tags ?? [],
            areaId: areaId, organizerId: organizerId, isBroadcast: isBroadcast ?? true)
    }
}

// MARK: - Errors

enum EventsAPIError: LocalizedError {
    case serverError
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .serverError: return "Server returned an error"
        case .notAuthenticated: return "You must be signed in"
        }
    }
}
