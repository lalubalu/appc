import Foundation
import CoreLocation
import SwiftUI
import Observation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseAuth

// MARK: - Events Service (SerpApi Google Events + Firestore community events)

/// Fetches real nearby events from SerpApi Google Events API and merges them
/// with user-created community events stored in Firestore.
///
/// SerpApi free tier: 100 searches/month, no credit card needed.
/// Sign up at https://serpapi.com to get an API key.
///
/// Falls back to sample data only when both sources fail/return empty.
@MainActor @Observable
final class EventsAPIService {

    // MARK: - Published State

    var events: [Event] = []
    var isLoading = false
    var lastError: String? = nil

    // MARK: - Configuration

    /// Set your SerpApi key here.
    /// Get one free at https://serpapi.com (100 searches/month)
    /// Reads SerpApi key from Info.plist (injected via Secrets.xcconfig at build time).
    /// Falls back to SERPAPI_KEY environment variable for CI/testing.
    private let serpApiKey: String = {
        if let key = Bundle.main.object(forInfoDictionaryKey: "SerpApiKey") as? String, !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["SERPAPI_KEY"], !key.isEmpty {
            return key
        }
        return ""
    }()

    // MARK: - Private

    private var db: Firestore { Firestore.firestore() }
    private let providerHub = EventProviderHub()
    /// Names of external event providers that are configured and will run.
    var enabledProviders: [String] { providerHub.enabledNames }
    private var lastFetchDate: Date?
    private var cachedCenter: CLLocationCoordinate2D?
    private let fetchCooldown: TimeInterval = 600 // 10 min — be conservative with 100 free searches
    private let maxEvents = 30
    private let searchRadiusMiles = 25

    // Cache
    private let cacheKey = "cachedEventsJSON"
    private let cacheCenterKey = "cachedEventsCenter"
    private let cacheTimestampKey = "cachedEventsTimestamp"
    private let cacheTTL: TimeInterval = 3600 // 1 hour — events don't change minute-to-minute

    // MARK: - Init

    init() {
        loadCachedEvents()
        if events.isEmpty {
            useSampleFallback()
        }
    }

    // MARK: - Public API

    /// Fetch nearby events from SerpApi + Firestore around a coordinate.
    func fetchNearbyEvents(around center: CLLocationCoordinate2D) async {
        // Skip if we fetched for a nearby coordinate recently
        if let cached = cachedCenter, let last = lastFetchDate,
           Date().timeIntervalSince(last) < fetchCooldown,
           distance(cached, center) < 5000 {
            return
        }

        // Run the network work in an UNSTRUCTURED task so it survives even if the
        // calling SwiftUI `.task` is cancelled by view-lifecycle churn at launch.
        await Task { @MainActor in
            self.isLoading = true
            self.lastError = nil

            // Fetch from all sources in parallel: SerpApi, Firestore community events,
            // and every configured external provider (Ticketmaster, Neighborhood Commons, …).
            async let serpEvents = self.fetchSerpApiEvents(around: center)
            async let communityEvents = self.fetchFirestoreEvents()
            async let externalEvents = self.providerHub.fetchAll(around: center, radiusMiles: self.searchRadiusMiles)

            let realEvents = await serpEvents
            let userEvents = await communityEvents
            let extEvents = await externalEvents

            // Merge: user-created events first, then real + external events, dedup by title.
            var merged: [Event] = userEvents
            var seenTitles = Set(merged.map { $0.title.lowercased() })
            for event in (realEvents + extEvents) where !seenTitles.contains(event.title.lowercased()) {
                merged.append(event)
                seenTitles.insert(event.title.lowercased())
            }
            merged.sort { $0.date < $1.date }

            if merged.isEmpty {
                if self.events.isEmpty { self.useSampleFallback() }
            } else {
                self.events = merged
                self.cachedCenter = center
                self.persistCache(center: center)
            }

            self.lastFetchDate = Date()
            self.isLoading = false
        }.value
    }

    /// Force refresh, ignoring cooldown
    func refresh(around center: CLLocationCoordinate2D) async {
        lastFetchDate = nil
        cachedCenter = nil
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        await fetchNearbyEvents(around: center)
    }

    /// Create a new community event and add it to Firestore.
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

        let data: [String: Any] = [
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
            "createdAt": FieldValue.serverTimestamp()
        ]

        do {
            try await db.collection("events").document(eventID).setData(data)

            let event = Event(
                id: eventID,
                title: title,
                organizer: organizer,
                date: date,
                time: time,
                locationName: locationName,
                attendeeCount: 1,
                maxAttendees: maxAttendees,
                category: category,
                imagePlaceholder: category.icon,
                pointValue: pointValue,
                description: description,
                creatorID: currentUser.uid
            )

            events.insert(event, at: 0)
            events.sort { $0.date < $1.date }
            return event
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Delete an event (only if current user is the creator)
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

    // MARK: - SerpApi Google Events

    private func fetchSerpApiEvents(around center: CLLocationCoordinate2D) async -> [Event] {
        guard !serpApiKey.isEmpty else { return [] }

        do {
            // Reverse geocode to get city name for the search query
            let cityName = await reverseGeocode(center) ?? "nearby"

            var components = URLComponents(string: "https://serpapi.com/search.json")!
            components.queryItems = [
                URLQueryItem(name: "engine", value: "google_events"),
                URLQueryItem(name: "q", value: "events in \(cityName)"),
                URLQueryItem(name: "api_key", value: serpApiKey),
            ]

            guard let url = components.url else { return [] }

            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            // Avoid the iOS Simulator's HTTP/3/QUIC hang (same fix as the other providers).
            request.assumesHTTP3Capable = false

            let (data, response) = try await providerSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }

            let decoded = try JSONDecoder().decode(SerpApiResponse.self, from: data)
            return mapSerpEvents(decoded.events_results ?? [])
        } catch {
            print("[EventsAPI] SerpApi error: \(error.localizedDescription)")
            return []
        }
    }

    private func mapSerpEvents(_ serpEvents: [SerpApiEvent]) -> [Event] {
        serpEvents.compactMap { serpEvent in
            // Skip paid events
            if isPaidEvent(serpEvent) { return nil }

            let title = serpEvent.title
            let id = "serp-\(title.hashValue)"

            // Parse date from SerpApi
            let date = parseSerpDate(serpEvent.date) ?? Date()

            // Build time string
            let time = serpEvent.date?.when ?? "Time TBA"

            // Venue / location
            let locationName = serpEvent.venue?.name
                ?? serpEvent.address?.first
                ?? "Location TBA"

            // Categorize
            let category = categorizeSerpEvent(title: title, description: serpEvent.description)
            let pointValue = category.defaultPoints

            // Organizer from venue or address
            let organizer = serpEvent.venue?.name ?? "Community"

            return Event(
                id: id,
                title: title,
                organizer: organizer,
                date: date,
                time: time,
                locationName: locationName,
                attendeeCount: Int.random(in: 10...120),
                maxAttendees: nil,
                category: category,
                imagePlaceholder: category.icon,
                pointValue: pointValue,
                description: serpEvent.description
            )
        }
    }

    /// Map event title/description keywords to our categories
    private func categorizeSerpEvent(title: String, description: String?) -> EventCategory {
        let text = "\(title) \(description ?? "")".lowercased()

        if text.contains("hackathon") || text.contains("hack night") || text.contains("coding") || text.contains("devfest") {
            return .hackathon
        }
        if text.contains("meetup") || text.contains("meet up") || text.contains("networking") {
            return .meetup
        }
        if text.contains("volunteer") || text.contains("cleanup") || text.contains("clean up") || text.contains("food drive") || text.contains("charity") {
            return .volunteer
        }
        if text.contains("workshop") || text.contains("class") || text.contains("seminar") || text.contains("learn") || text.contains("training") {
            return .workshop
        }
        if text.contains("market") || text.contains("fair") || text.contains("bazaar") || text.contains("flea") {
            return .market
        }
        if text.contains("festival") || text.contains("fest ") || text.contains("celebration") {
            return .festival
        }
        if text.contains("sport") || text.contains("run ") || text.contains("basketball") || text.contains("soccer") || text.contains("tournament") || text.contains("yoga") || text.contains("fitness") {
            return .sports
        }
        if text.contains("cleanup") || text.contains("clean-up") || text.contains("trash") {
            return .cleanup
        }

        return .social
    }

    /// Parse SerpApi date object into a Date
    private func parseSerpDate(_ dateObj: SerpApiDate?) -> Date? {
        guard let dateObj else { return nil }

        // Try start_date first (format: "Mar 29" or "Mar 29, 2026")
        if let startDate = dateObj.start_date {
            let formatters: [String] = ["MMM d, yyyy", "MMM d"]
            for format in formatters {
                let f = DateFormatter()
                f.dateFormat = format
                f.locale = Locale(identifier: "en_US_POSIX")
                if let parsed = f.date(from: startDate) {
                    // If no year was parsed, assume current year
                    if !format.contains("yyyy") {
                        let cal = Calendar.current
                        var comps = cal.dateComponents([.month, .day], from: parsed)
                        comps.year = cal.component(.year, from: Date())
                        if let withYear = cal.date(from: comps) {
                            // If the date is in the past, assume next year
                            return withYear < Date()
                                ? cal.date(byAdding: .year, value: 1, to: withYear)
                                : withYear
                        }
                    }
                    return parsed
                }
            }
        }

        // Fallback: try to extract from "when" string
        if let when = dateObj.when {
            if when.lowercased().contains("today") { return Date() }
            if when.lowercased().contains("tomorrow") {
                return Calendar.current.date(byAdding: .day, value: 1, to: Date())
            }
        }

        return nil
    }

    /// Check if an event should be excluded (paid, trade shows, concerts, etc.)
    private func isPaidEvent(_ event: SerpApiEvent) -> Bool {
        let text = "\(event.title) \(event.description ?? "")".lowercased()

        // Check ticket_info for "tickets" link type (vs "more info" or "register")
        if let tickets = event.ticket_info {
            for ticket in tickets {
                let linkType = (ticket.link_type ?? "").lowercased()
                if linkType == "tickets" || linkType == "buy tickets" {
                    return true
                }
                // Trade show / expo listing sites
                let source = (ticket.source ?? "").lowercased()
                if source.contains("tradeindia") || source.contains("tradefair")
                    || source.contains("neventum") || source.contains("boothsquare")
                    || source.contains("spotify") {
                    return true
                }
            }
        }

        // Paid / non-community keywords
        let excludeKeywords = [
            "buy tickets", "ticket price", "admission fee", "paid event",
            "starting at $", "starting at ₹", "cover charge", "entry fee",
            "trade show", "tradeshow", "trade fair", "expo ", "exhibition", "b2b",
            "concert", "live music tour", "stand-up comedy show"
        ]
        for keyword in excludeKeywords {
            if text.contains(keyword) { return true }
        }

        return false
    }

    /// Reverse geocode coordinate to a city name for the search query
    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let city = placemarks.first?.locality,
               let state = placemarks.first?.administrativeArea {
                return "\(city), \(state)"
            }
            return placemarks.first?.locality
        } catch {
            return nil
        }
    }

    // MARK: - Firestore Community Events

    private func fetchFirestoreEvents() async -> [Event] {
        guard Auth.auth().currentUser != nil else { return [] }

        do {
            let now = Timestamp(date: Date())
            let snapshot = try await db.collection("events")
                .whereField("date", isGreaterThanOrEqualTo: now)
                .order(by: "date")
                .limit(to: maxEvents)
                .getDocuments()

            return snapshot.documents.compactMap { mapFirestoreDocument($0) }
        } catch {
            print("[EventsAPI] Firestore error: \(error.localizedDescription)")
            return []
        }
    }

    private func mapFirestoreDocument(_ doc: DocumentSnapshot) -> Event? {
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

        return Event(
            id: doc.documentID,
            title: title,
            organizer: organizer,
            date: timestamp.dateValue(),
            time: time,
            locationName: locationName,
            attendeeCount: data["attendeeCount"] as? Int ?? 0,
            maxAttendees: data["maxAttendees"] as? Int,
            category: category,
            imagePlaceholder: data["imagePlaceholder"] as? String ?? category.icon,
            pointValue: data["pointValue"] as? Int ?? category.defaultPoints,
            description: data["description"] as? String,
            creatorID: data["creatorID"] as? String
        )
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
        events = cached.map { $0.toEvent() }
    }

    private func isCacheValid() -> Bool {
        let ts = UserDefaults.standard.double(forKey: cacheTimestampKey)
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < cacheTTL
    }

    // MARK: - Helpers

    private func useSampleFallback() {
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

// MARK: - SerpApi Response Models

private struct SerpApiResponse: Decodable {
    let events_results: [SerpApiEvent]?
}

private struct SerpApiEvent: Decodable {
    let title: String
    let date: SerpApiDate?
    let address: [String]?
    let link: String?
    let description: String?
    let venue: SerpApiVenue?
    let thumbnail: String?
    let ticket_info: [SerpApiTicket]?
}

private struct SerpApiTicket: Decodable {
    let source: String?
    let link: String?
    let link_type: String?
}

private struct SerpApiDate: Decodable {
    let start_date: String?
    let when: String?
}

private struct SerpApiVenue: Decodable {
    let name: String?
    let rating: Double?
    let reviews: Int?
    let link: String?
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

    init(from event: Event) {
        self.id = event.id
        self.title = event.title
        self.organizer = event.organizer
        self.dateInterval = event.date.timeIntervalSince1970
        self.time = event.time
        self.locationName = event.locationName
        self.attendeeCount = event.attendeeCount
        self.maxAttendees = event.maxAttendees
        self.categoryRaw = event.category.rawValue
        self.imagePlaceholder = event.imagePlaceholder
        self.pointValue = event.pointValue
        self.description = event.description
        self.creatorID = event.creatorID
    }

    func toEvent() -> Event {
        let category = EventCategory(rawValue: categoryRaw) ?? .social
        return Event(
            id: id,
            title: title,
            organizer: organizer,
            date: Date(timeIntervalSince1970: dateInterval),
            time: time,
            locationName: locationName,
            attendeeCount: attendeeCount,
            maxAttendees: maxAttendees,
            category: category,
            imagePlaceholder: imagePlaceholder,
            pointValue: pointValue,
            description: description,
            creatorID: creatorID
        )
    }
}

// MARK: - Errors

enum EventsAPIError: LocalizedError {
    case invalidURL
    case serverError
    case rateLimited
    case decodingError
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .serverError: return "Server returned an error"
        case .rateLimited: return "Rate limit exceeded. Please try again later."
        case .decodingError: return "Could not parse event response"
        case .notAuthenticated: return "You must be signed in"
        }
    }
}
