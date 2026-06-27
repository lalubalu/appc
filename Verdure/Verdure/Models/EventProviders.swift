import Foundation
import CoreLocation

// =====================================================================
//  Pluggable external event sources.
//
//  Each provider reads its credentials from Info.plist (injected at build
//  time from Secrets.xcconfig). A provider with no key/config is *disabled*
//  and returns [] — so the app keeps working (falls back to SerpApi + sample
//  data) until real keys are supplied. EventProviderHub fans out to every
//  enabled provider in parallel and merges the results.
//
//  Reality notes (see each provider):
//   • Ticketmaster Discovery — fully functional with a free API key.
//   • Eventbrite — public *search* was retired (2019); only org events work.
//   • Localist — per-institution; needs a specific calendar host.
//   • Google Programmable Search — returns web links, not structured events.
//   • Neighborhood Commons — endpoint unverified; disabled until configured.
// =====================================================================

// MARK: - Provider protocol

protocol EventProvider: Sendable {
    var name: String { get }
    var isEnabled: Bool { get }
    func fetchEvents(around center: CLLocationCoordinate2D, radiusMiles: Int) async -> [Event]
}

// MARK: - Config + shared helpers

enum ProviderConfig {
    /// Read a build-time secret from Info.plist (injected from Secrets.xcconfig),
    /// falling back to an environment variable. Treats unexpanded "$(VAR)" as empty.
    static func value(_ infoKey: String, env: String? = nil) -> String {
        if let v = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
           !v.isEmpty, !v.hasPrefix("$(") { return v }
        if let env, let v = ProcessInfo.processInfo.environment[env], !v.isEmpty { return v }
        return ""
    }
}

enum EventParse {
    // DateFormatter/ISO8601DateFormatter are used read-only for parsing; safe to share.
    nonisolated(unsafe) static let ymd: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    nonisolated(unsafe) static let localDateTime: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f
    }()
    nonisolated(unsafe) static let timeOut: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"; return f
    }()
    nonisolated(unsafe) static let isoZ = ISO8601DateFormatter()

    /// Parse a variety of date strings external APIs return.
    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = localDateTime.date(from: s) { return d }
        if let d = isoZ.date(from: s) { return d }
        if let d = ymd.date(from: String(s.prefix(10))) { return d }
        return nil
    }

    static func timeString(from date: Date) -> String { timeOut.string(from: date) }
}

extension EventCategory {
    /// Best-effort classification from free text (titles, genres, snippets).
    static func classify(_ text: String) -> EventCategory {
        let t = text.lowercased()
        if t.contains("clean") || t.contains("litter") { return .cleanup }
        if t.contains("volunteer") || t.contains("charity") || t.contains("nonprofit") || t.contains("fundrais") { return .volunteer }
        if t.contains("hack") { return .hackathon }
        if t.contains("workshop") || t.contains("class") || t.contains("seminar") || t.contains("training") || t.contains("lecture") { return .workshop }
        if t.contains("market") || t.contains("farmers") || t.contains("craft fair") { return .market }
        if t.contains("festival") || t.contains("concert") || t.contains("music") || t.contains("comedy") || t.contains("theatre") || t.contains("theater") { return .festival }
        if t.contains("sport") || t.contains("game") || t.contains("run") || t.contains("yoga") || t.contains("fitness") || t.contains("race") || t.contains("hike") { return .sports }
        if t.contains("network") || t.contains("meetup") || t.contains("meet up") || t.contains("student") { return .meetup }
        return .social
    }
}

private func makeEvent(id: String, title: String, organizer: String, date: Date,
                       locationName: String, category: EventCategory, website: String?) -> Event {
    Event(id: id,
          title: title,
          organizer: organizer.isEmpty ? "Community" : organizer,
          date: date,
          time: EventParse.timeString(from: date),
          locationName: locationName.isEmpty ? "See website" : locationName,
          attendeeCount: 0,
          maxAttendees: nil,
          category: category,
          imagePlaceholder: category.icon,
          pointValue: category.defaultPoints,
          description: nil,
          creatorID: nil,
          website: website)
}

// Ephemeral session (no Alt-Svc cache) so the first request isn't pushed onto HTTP/3.
let providerSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 15
    config.waitsForConnectivity = true
    return URLSession(configuration: config)
}()

/// Shared GET-JSON helper used by every provider (events + places). Disables HTTP/3 to
/// dodge the iOS Simulator's QUIC hang.
func fetchJSON(_ url: URL, headers: [String: String] = [:]) async -> Data? {
    var req = URLRequest(url: url)
    req.timeoutInterval = 15
    // Don't proactively use HTTP/3 — the iOS Simulator's QUIC stack hangs on some
    // Cloudflare-fronted hosts (e.g. Neighborhood Commons), causing -1001 timeouts.
    req.assumesHTTP3Capable = false
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    do {
        let (data, resp) = try await providerSession.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { return nil }
        return data
    } catch { return nil }
}

// MARK: - Ticketmaster Discovery API
// Docs: https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/

struct TicketmasterProvider: EventProvider {
    let name = "Ticketmaster"
    private var key: String { ProviderConfig.value("TicketmasterKey", env: "TICKETMASTER_KEY") }
    var isEnabled: Bool { !key.isEmpty }

    func fetchEvents(around center: CLLocationCoordinate2D, radiusMiles: Int) async -> [Event] {
        guard isEnabled else { return [] }
        var comps = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events.json")!
        comps.queryItems = [
            .init(name: "apikey", value: key),
            .init(name: "latlong", value: "\(center.latitude),\(center.longitude)"),
            .init(name: "radius", value: "\(radiusMiles)"),
            .init(name: "unit", value: "miles"),
            .init(name: "size", value: "30"),
            .init(name: "sort", value: "date,asc")
        ]
        guard let url = comps.url, let data = await fetchJSON(url) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedded = root["_embedded"] as? [String: Any],
              let events = embedded["events"] as? [[String: Any]] else { return [] }

        return events.compactMap { ev in
            guard let id = ev["id"] as? String, let title = ev["name"] as? String else { return nil }
            let dates = ev["dates"] as? [String: Any]
            let start = dates?["start"] as? [String: Any]
            let localDate = start?["localDate"] as? String
            let localTime = start?["localTime"] as? String ?? "19:00:00"
            guard let day = localDate, let date = EventParse.date("\(day)T\(localTime)") ?? EventParse.date(day) else { return nil }
            let venues = (ev["_embedded"] as? [String: Any])?["venues"] as? [[String: Any]]
            let venueName = venues?.first?["name"] as? String ?? ""
            let classification = (ev["classifications"] as? [[String: Any]])?.first
            let segment = (classification?["segment"] as? [String: Any])?["name"] as? String
            let genreName = (classification?["genre"] as? [String: Any])?["name"] as? String
            let genre = segment ?? genreName ?? title
            return makeEvent(id: "tm-\(id)", title: title, organizer: venueName, date: date,
                             locationName: venueName, category: .classify(genre),
                             website: ev["url"] as? String)
        }
    }
}

// MARK: - SeatGeek API
// Docs: https://platform.seatgeek.com — free client_id, full geo search.
// GET https://api.seatgeek.com/2/events?lat=&lon=&range=30mi&client_id=…

struct SeatGeekProvider: EventProvider {
    let name = "SeatGeek"
    private var clientID: String { ProviderConfig.value("SeatGeekClientId", env: "SEATGEEK_CLIENT_ID") }
    var isEnabled: Bool { !clientID.isEmpty }

    func fetchEvents(around center: CLLocationCoordinate2D, radiusMiles: Int) async -> [Event] {
        guard isEnabled else { return [] }
        var comps = URLComponents(string: "https://api.seatgeek.com/2/events")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "lat", value: "\(center.latitude)"),
            .init(name: "lon", value: "\(center.longitude)"),
            .init(name: "range", value: "\(radiusMiles)mi"),
            .init(name: "per_page", value: "30"),
            .init(name: "sort", value: "datetime_local.asc")
        ]
        guard let url = comps.url, let data = await fetchJSON(url) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }

        return events.compactMap { ev in
            let id = (ev["id"] as? Int).map(String.init) ?? (ev["id"] as? String) ?? UUID().uuidString
            guard let title = ev["title"] as? String,
                  let date = EventParse.date(ev["datetime_local"] as? String) else { return nil }
            let venue = ev["venue"] as? [String: Any]
            let venueName = venue?["name"] as? String ?? ""
            let type = ev["type"] as? String ?? ""
            return makeEvent(id: "sg-\(id)", title: title, organizer: venueName, date: date,
                             locationName: venueName, category: .classify("\(type) \(title)"),
                             website: ev["url"] as? String)
        }
    }
}

// MARK: - Eventbrite API
// Docs: https://www.eventbrite.com/platform/api
// NOTE: Public event *search* was retired in 2019. The v3 API now only returns
// events belonging to YOUR organization, so this needs both a private token and
// your organization ID. Hyperlocal/discovery search is no longer possible here.

struct EventbriteProvider: EventProvider {
    let name = "Eventbrite"
    private var token: String { ProviderConfig.value("EventbriteToken", env: "EVENTBRITE_TOKEN") }
    private var configuredOrgID: String { ProviderConfig.value("EventbriteOrgId", env: "EVENTBRITE_ORG_ID") }
    var isEnabled: Bool { !token.isEmpty }   // org id is auto-discovered from the token

    /// The token's first organization (Eventbrite only lets you list your own org's events).
    private func resolveOrgID() async -> String? {
        if !configuredOrgID.isEmpty { return configuredOrgID }
        let url = URL(string: "https://www.eventbriteapi.com/v3/users/me/organizations/")!
        guard let data = await fetchJSON(url, headers: ["Authorization": "Bearer \(token)"]),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let orgs = root["organizations"] as? [[String: Any]] else { return nil }
        return orgs.first?["id"] as? String
    }

    func fetchEvents(around center: CLLocationCoordinate2D, radiusMiles: Int) async -> [Event] {
        guard isEnabled, let orgID = await resolveOrgID() else { return [] }
        var comps = URLComponents(string: "https://www.eventbriteapi.com/v3/organizations/\(orgID)/events/")!
        comps.queryItems = [
            .init(name: "status", value: "live"),
            .init(name: "expand", value: "venue"),
            .init(name: "order_by", value: "start_asc")
        ]
        guard let url = comps.url,
              let data = await fetchJSON(url, headers: ["Authorization": "Bearer \(token)"]) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }

        return events.compactMap { ev in
            guard let id = ev["id"] as? String,
                  let title = (ev["name"] as? [String: Any])?["text"] as? String else { return nil }
            let startLocal = (ev["start"] as? [String: Any])?["local"] as? String
            guard let date = EventParse.date(startLocal) else { return nil }
            let venue = ev["venue"] as? [String: Any]
            let venueName = venue?["name"] as? String ?? ""
            let summary = (ev["summary"] as? String) ?? title
            return makeEvent(id: "eb-\(id)", title: title, organizer: "Eventbrite", date: date,
                             locationName: venueName, category: .classify("\(title) \(summary)"),
                             website: ev["url"] as? String)
        }
    }
}

// MARK: - Localist API
// Docs: https://developer.localist.com/doc/api
// Per-institution: each Localist calendar lives on its own host. Configure the
// host (e.g. "calendar.your-school.edu") via Secrets — there is no global endpoint.

struct LocalistProvider: EventProvider {
    let name = "Localist"
    private var host: String { ProviderConfig.value("LocalistHost", env: "LOCALIST_HOST") }
    var isEnabled: Bool { !host.isEmpty }

    func fetchEvents(around center: CLLocationCoordinate2D, radiusMiles: Int) async -> [Event] {
        guard isEnabled else { return [] }
        let cleanHost = host.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "/", with: "")
        var comps = URLComponents(string: "https://\(cleanHost)/api/2/events")!
        // Localist geo params: near="lat,lng", within=radius, units=mi (verified against docs).
        comps.queryItems = [
            .init(name: "days", value: "60"),
            .init(name: "pp", value: "30"),
            .init(name: "near", value: "\(center.latitude),\(center.longitude)"),
            .init(name: "within", value: "\(radiusMiles)"),
            .init(name: "units", value: "mi")
        ]
        guard let url = comps.url, let data = await fetchJSON(url) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wrappers = root["events"] as? [[String: Any]] else { return [] }

        return wrappers.compactMap { wrapper in
            guard let ev = wrapper["event"] as? [String: Any],
                  let id = ev["id"], let title = ev["title"] as? String else { return nil }
            let instances = ev["event_instances"] as? [[String: Any]]
            let firstStart = (instances?.first?["event_instance"] as? [String: Any])?["start"] as? String
            guard let date = EventParse.date(firstStart) else { return nil }
            let locationName = (ev["location_name"] as? String) ?? (ev["location"] as? String) ?? ""
            let desc = (ev["description_text"] as? String) ?? title
            return makeEvent(id: "lo-\(id)", title: title, organizer: cleanHost, date: date,
                             locationName: locationName, category: .classify("\(title) \(desc)"),
                             website: ev["localist_url"] as? String)
        }
    }
}

// MARK: - Google Programmable Search Engine (Custom Search JSON API)
// Docs: https://developers.google.com/custom-search/v1/overview
// Returns web results, not structured events — so dates/venues aren't reliable.
// Used as a best-effort discovery layer that surfaces event *links*.
// VERIFIED 2026-06: endpoint/fields correct; free tier = 100 queries/day. BUT the
// Custom Search JSON API is "closed to new customers" and is scheduled to shut down
// on 2027-01-01 — only existing API consumers can obtain a key. Treat as legacy.

struct GooglePSEProvider: EventProvider {
    let name = "Google Search"
    private var key: String { ProviderConfig.value("GooglePSEKey", env: "GOOGLE_PSE_KEY") }
    private var cx: String { ProviderConfig.value("GooglePSECx", env: "GOOGLE_PSE_CX") }
    var isEnabled: Bool { !key.isEmpty && !cx.isEmpty }

    func fetchEvents(around center: CLLocationCoordinate2D, radiusMiles: Int) async -> [Event] {
        guard isEnabled else { return [] }
        var comps = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
        comps.queryItems = [
            .init(name: "key", value: key),
            .init(name: "cx", value: cx),
            .init(name: "q", value: "community events workshops near \(center.latitude),\(center.longitude)"),
            .init(name: "num", value: "10")
        ]
        guard let url = comps.url, let data = await fetchJSON(url) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }

        // No structured dates from web results — schedule as "upcoming" so they list,
        // but clearly sourced from a link.
        let base = Date().addingTimeInterval(86_400)
        return items.enumerated().compactMap { idx, item in
            guard let title = item["title"] as? String, let link = item["link"] as? String else { return nil }
            let snippet = (item["snippet"] as? String) ?? ""
            let date = base.addingTimeInterval(Double(idx) * 86_400)
            return makeEvent(id: "gx-\(abs(link.hashValue))", title: title, organizer: "Web",
                             date: date, locationName: "See website",
                             category: .classify("\(title) \(snippet)"), website: link)
        }
    }
}

// MARK: - Neighborhood Commons API
// Docs: https://neighborhood-commons.org  (open, Schema.org-aligned neighborhood data)
// VERIFIED 2026-06 LIVE: GET https://neighborhood-commons.org/api/v1/events?near=lat,lng&radius_km=N
// returns {meta, events:[…]} with NO auth required. Currently serves Philadelphia only, so it
// returns [] elsewhere (harmless). Enabled by default — override the base via
// NEIGHBORHOOD_COMMONS_BASE, or set it to "off" to disable.

struct NeighborhoodCommonsProvider: EventProvider {
    let name = "Neighborhood Commons"
    private var base: String {
        let configured = ProviderConfig.value("NeighborhoodCommonsBase", env: "NEIGHBORHOOD_COMMONS_BASE")
        return configured.isEmpty ? "https://neighborhood-commons.org/api/v1" : configured
    }
    // Free public reads — on by default. Set the base to "off" to opt out.
    var isEnabled: Bool { base.lowercased() != "off" }

    func fetchEvents(around center: CLLocationCoordinate2D, radiusMiles: Int) async -> [Event] {
        guard isEnabled else { return [] }
        let cleanBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let radiusKm = max(1, Int((Double(radiusMiles) * 1.60934).rounded()))
        var comps = URLComponents(string: "\(cleanBase)/events")!
        comps.queryItems = [
            .init(name: "near", value: "\(center.latitude),\(center.longitude)"),
            .init(name: "radius_km", value: "\(radiusKm)"),
            .init(name: "collapse_series", value: "true"),
            .init(name: "limit", value: "30")
        ]
        guard let url = comps.url, let data = await fetchJSON(url) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }

        return events.compactMap { ev in
            guard let id = ev["id"] as? String, let title = ev["name"] as? String,
                  let date = EventParse.date(ev["start"] as? String) else { return nil }
            let location = ev["location"] as? [String: Any]
            let locationName = (location?["name"] as? String) ?? (location?["address"] as? String) ?? ""
            let org = (ev["organizer"] as? [String: Any])?["name"] as? String ?? "Local"
            // category is an array of slugs (e.g. ["happy-hour"]).
            let cats = (ev["category"] as? [String])?.joined(separator: " ") ?? ""
            let desc = ev["description"] as? String ?? ""
            return makeEvent(id: "nc-\(id)", title: title, organizer: org, date: date,
                             locationName: locationName,
                             category: .classify("\(cats) \(title) \(desc)"),
                             website: ev["url"] as? String)
        }
    }
}

// MARK: - Hub (parallel fan-out + merge)

@MainActor
final class EventProviderHub {
    let providers: [EventProvider] = [
        TicketmasterProvider(),
        SeatGeekProvider(),
        EventbriteProvider(),
        LocalistProvider(),
        GooglePSEProvider(),
        NeighborhoodCommonsProvider()
    ]

    /// Names of providers that are configured and will actually run.
    var enabledNames: [String] { providers.filter(\.isEnabled).map(\.name) }

    /// Fetch from every enabled provider concurrently and flatten the results.
    func fetchAll(around center: CLLocationCoordinate2D, radiusMiles: Int) async -> [Event] {
        let active = providers.filter(\.isEnabled)
        guard !active.isEmpty else { return [] }
        var all: [Event] = []
        await withTaskGroup(of: [Event].self) { group in
            for provider in active {
                group.addTask { await provider.fetchEvents(around: center, radiusMiles: radiusMiles) }
            }
            for await batch in group { all.append(contentsOf: batch) }
        }
        return all
    }
}
