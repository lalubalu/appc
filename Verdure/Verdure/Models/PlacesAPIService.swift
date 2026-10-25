import Foundation
import CoreLocation
import SwiftUI
import Observation

// MARK: - Places API Service (Overpass / OpenStreetMap)

/// The HTTP call the service makes; tests inject one that answers from fixtures.
typealias PlacesTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Where the places on screen came from. The credit shows the snapshot date when
/// the bundled snapshot is what the user is looking at.
enum PlacesSource: Equatable {
    case none
    /// A live Overpass answer, naming the mirror that gave it.
    case live(mirror: String)
    /// The per-area on-device cache (from an earlier live answer).
    case cache
    /// The OpenStreetMap snapshot bundled with the app, with its capture date.
    case snapshot(date: String)
}

/// The OpenStreetMap extract shipped in the bundle (Resources/osm-snapshot-san-jose.json):
/// the app's own Overpass query for the launch area, captured once so that the
/// first launch and every launch with Overpass at capacity still has real places.
/// It is the same data the live path returns, so the ODbL credit is the same.
struct OSMSnapshot: Decodable {
    struct Center: Decodable { let lat: Double; let lon: Double }
    let center: Center
    let radiusMeters: Double
    /// ISO-8601 capture time, shown next to the credit as "snapshot <date>".
    let fetchedAt: String
    let endpoint: String
    let attribution: String
    let elements: [OSMElement]

    static let resourceName = "osm-snapshot-san-jose"

    static func bundled(in bundle: Bundle = .main) -> OSMSnapshot? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OSMSnapshot.self, from: data)
    }

    /// The snapshot is only honest near where it was captured: within its radius plus 10 km.
    func covers(_ c: CLLocationCoordinate2D) -> Bool {
        let a = CLLocation(latitude: center.lat, longitude: center.lon)
        let b = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return a.distance(from: b) <= radiusMeters + 10_000
    }

    /// "2026-10-25" from the capture time.
    var dateLabel: String { String(fetchedAt.prefix(10)) }
}

@MainActor @Observable
final class PlacesAPIService {

    // MARK: - Published State

    var places: [Place] = []
    var collectiblePlaces: [CollectiblePlace] = []
    var isLoading = false
    var lastError: String? = nil
    /// What the current `places` came from; drives the credit's snapshot date.
    private(set) var source: PlacesSource = .none

    /// The date to show after "© OpenStreetMap contributors" when the bundled
    /// snapshot is on screen; nil for live or cached answers.
    var snapshotDate: String? {
        if case .snapshot(let date) = source { return date }
        return nil
    }

    // MARK: - Private

    private var cachedCenter: CLLocationCoordinate2D?
    private let maxPlaces = 30
    private let radiusMeters = 5000 // 5 km search radius
    /// Per-area cache (CAC 2026, 1.4): keys carry the area cell so a cache for
    /// one neighbourhood is never served for another. One cell ≈ 5.5 km.
    private static let cachePrefix = "cachedPlaces.v3"
    private static let lastAreaKey = "cachedPlaces.v3.lastArea"
    private let cacheTTL: TimeInterval = 3600 // 1 hour
    private let transport: PlacesTransport
    private let snapshot: OSMSnapshot?

    /// Overpass mirrors, tried in order with a 25-second limit each. The public
    /// instance was at capacity for a whole night on 2026-10-22; the others
    /// are community mirrors of the same data.
    static let overpassMirrors: [String] = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]
    static let mirrorTimeout: TimeInterval = 25
    /// Identifies the app to Overpass (it answers 406 to generic agents). No personal address.
    static let userAgent = "Verdure/1.0 (+https://verdure-app.com)"

    // MARK: - Init

    init(transport: PlacesTransport? = nil, snapshot: OSMSnapshot? = OSMSnapshot.bundled()) {
        self.transport = transport ?? { request in try await URLSession.shared.data(for: request) }
        self.snapshot = snapshot
        if let last = UserDefaults.standard.string(forKey: Self.lastAreaKey) { loadCachedPlaces(areaKey: last) }
        if places.isEmpty {
            useSampleFallback()
        }
    }

    /// ~5.5 km cells, so a cache is only reused where it was fetched.
    static func areaKey(_ c: CLLocationCoordinate2D) -> String {
        "\(Int((c.latitude * 20).rounded(.down)))_\(Int((c.longitude * 20).rounded(.down)))"
    }

    // MARK: - Public API

    /// Fetch nearby places from Overpass API around a coordinate.
    /// Falls back to SampleData on failure.
    func fetchNearbyPlaces(around center: CLLocationCoordinate2D) async {
        if QAData.offline { return }   // QA: cached/sample data only
        let key = Self.areaKey(center)
        // Skip if we already fetched for a nearby coordinate recently
        if let cached = cachedCenter, isCacheValid(areaKey: key),
           distance(cached, center) < 500 { // within 500m of cached center
            return
        }

        isLoading = true
        lastError = nil

        // Unstructured task so a cancelled SwiftUI .task can't kill the fetch.
        await Task { @MainActor in
            // Primary source: OpenStreetMap / Overpass (free, no key, global),
            // through the mirror list; then this area's cache; then the bundled
            // snapshot. Each step is real OpenStreetMap data — never a sample.
            var merged: [Place] = []
            var liveSource: PlacesSource = .none
            do {
                let (osmElements, mirror) = try await self.queryOverpass(center: center)
                merged = self.mapToPlaces(osmElements, center: center)
                liveSource = .live(mirror: mirror)
            } catch {
                self.lastError = error.localizedDescription
                if let cached = self.cachedPlaces(areaKey: key), !cached.isEmpty {
                    merged = cached
                    liveSource = .cache
                } else if let snap = self.snapshot, snap.covers(center) {
                    merged = self.mapToPlaces(snap.elements, center: center)
                    liveSource = .snapshot(date: snap.dateLabel)
                }
            }

            // Additional free sources — no-ops unless their keys are configured.
            async let recreation = self.fetchRecreationFacilities(center: center)
            async let nationalParks = self.fetchNPSParks(center: center)
            let extra = await recreation + (await nationalParks)

            var seen = Set(merged.map { $0.name.lowercased() })
            for place in extra where !seen.contains(place.name.lowercased()) {
                merged.append(place)
                seen.insert(place.name.lowercased())
            }
            merged.sort { $0.distanceValue < $1.distanceValue }

            if merged.isEmpty {
                if self.places.isEmpty { self.useSampleFallback() }
            } else {
                self.places = Array(merged.prefix(self.maxPlaces + 15))
                self.collectiblePlaces = Self.buildCollectibles(from: self.places, center: center)
                self.cachedCenter = center
                self.source = liveSource
                // Only a live answer refreshes the per-area cache; a snapshot or an
                // old cache is not re-stamped as fresh.
                if case .live = liveSource { self.persistCache(center: center, areaKey: key) }
            }
            self.isLoading = false
        }.value
    }

    /// Find the CollectiblePlace wrapper for a given Place
    func collectible(for place: Place) -> CollectiblePlace? {
        collectiblePlaces.first { $0.place.id == place.id }
    }

    // MARK: - Overpass Query

    /// The app's Overpass query, exported so the snapshot capture uses the same one.
    static func overpassQuery(center: CLLocationCoordinate2D, radiusMeters r: Int, limit: Int) -> String {
        let lat = center.latitude
        let lon = center.longitude
        // Query parks, trails, gardens, playgrounds, waterfront, sports, scenic, community spaces
        return """
        [out:json][timeout:25];
        (
          node["leisure"="park"](around:\(r),\(lat),\(lon));
          way["leisure"="park"](around:\(r),\(lat),\(lon));
          node["highway"="path"]["name"](around:\(r),\(lat),\(lon));
          way["highway"="path"]["name"](around:\(r),\(lat),\(lon));
          node["leisure"="garden"](around:\(r),\(lat),\(lon));
          way["leisure"="garden"](around:\(r),\(lat),\(lon));
          node["leisure"="playground"](around:\(r),\(lat),\(lon));
          node["natural"="water"]["name"](around:\(r),\(lat),\(lon));
          way["natural"="water"]["name"](around:\(r),\(lat),\(lon));
          node["leisure"="sports_centre"](around:\(r),\(lat),\(lon));
          node["leisure"="pitch"](around:\(r),\(lat),\(lon));
          node["tourism"="viewpoint"](around:\(r),\(lat),\(lon));
          node["amenity"="community_centre"](around:\(r),\(lat),\(lon));
          way["leisure"="nature_reserve"](around:\(r),\(lat),\(lon));
          node["natural"="beach"](around:\(r),\(lat),\(lon));
        );
        out center body qt \(limit);
        """
    }

    /// Ask each mirror in turn (25 s each) and return the first good answer with
    /// the mirror that gave it. Throws `allMirrorsFailed` with the last error
    /// when none answers, so the caller can fall back to the cache or snapshot.
    private func queryOverpass(center: CLLocationCoordinate2D) async throws -> ([OSMElement], String) {
        let query = Self.overpassQuery(center: center, radiusMeters: radiusMeters, limit: maxPlaces * 2)
        var lastFailure = "no mirror answered"
        for mirror in Self.overpassMirrors {
            guard let url = URL(string: mirror) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = "data=\(query)".data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            // Overpass answers 406 to generic agents (seen 2026-10-22); identify the app.
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = Self.mirrorTimeout
            do {
                let (data, response) = try await transport(request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    lastFailure = "\(url.host ?? mirror): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                    continue
                }
                let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
                return (decoded.elements, url.host ?? mirror)
            } catch {
                lastFailure = "\(url.host ?? mirror): \(error.localizedDescription)"
                continue
            }
        }
        throw PlacesAPIError.allMirrorsFailed(lastFailure)
    }

    // MARK: - Mapping OSM -> Place

    private func mapToPlaces(_ elements: [OSMElement], center: CLLocationCoordinate2D) -> [Place] {
        var seen = Set<String>() // deduplicate by name
        var results: [Place] = []

        for element in elements {
            let name = Sanitize.text(element.tags?["name"], max: 100)
            guard !name.isEmpty else { continue }

            let normalizedName = name.lowercased()
            guard !seen.contains(normalizedName) else { continue }
            seen.insert(normalizedName)

            let lat = element.lat ?? element.center?.lat ?? 0
            let lon = element.lon ?? element.center?.lon ?? 0
            guard lat != 0 && lon != 0 else { continue }

            let category = Self.categorize(element.tags ?? [:])
            let dist = Self.haversineDistance(
                lat1: center.latitude, lon1: center.longitude,
                lat2: lat, lon2: lon
            )
            let distMiles = dist / 1609.34

            let tags = element.tags ?? [:]
            let place = Place(
                id: "osm-\(element.id)",
                name: name,
                category: category,
                shortDescription: Sanitize.text(Self.buildDescription(tags: tags, category: category, name: name), max: 180),
                distance: String(format: "%.1f mi", distMiles),
                distanceValue: distMiles,
                rating: nil,          // OSM has no ratings — never fabricate one
                reviewCount: nil,
                imagePlaceholder: category.icon,
                accentColor: category.tint,
                isFeatured: distMiles < 0.5,
                latitude: lat,        // REAL coordinates → map pins + collect proximity
                longitude: lon,
                photoURL: Sanitize.url(tags["image"]),
                openHoursReal: Sanitize.text(tags["opening_hours"], max: 80).isEmpty ? nil
                    : Sanitize.text(tags["opening_hours"], max: 80)
            )

            results.append(place)
            if results.count >= maxPlaces { break }
        }

        // Sort by distance
        return results.sorted { $0.distanceValue < $1.distanceValue }
    }

    // MARK: - Category Mapping

    private static func categorize(_ tags: [String: String]) -> PlaceCategory {
        let leisure = tags["leisure"] ?? ""
        let highway = tags["highway"] ?? ""
        let natural = tags["natural"] ?? ""
        let tourism = tags["tourism"] ?? ""
        let amenity = tags["amenity"] ?? ""

        if leisure == "garden" { return .gardens }
        if leisure == "playground" { return .playgrounds }
        if leisure == "sports_centre" || leisure == "pitch" { return .sports }
        if leisure == "nature_reserve" { return .scenic }
        if highway == "path" || highway == "footway" { return .trails }
        if natural == "water" || natural == "beach" { return .waterfront }
        if tourism == "viewpoint" { return .scenic }
        if amenity == "community_centre" { return .community }
        if leisure == "park" { return .parks }

        return .parks // default
    }

    // MARK: - Synthetic Metadata

    private static func buildDescription(tags: [String: String], category: PlaceCategory, name: String) -> String {
        var parts: [String] = []

        if let surface = tags["surface"] {
            parts.append("Surface: \(surface).")
        }
        if tags["wheelchair"] == "yes" {
            parts.append("Wheelchair accessible.")
        }
        if tags["dog"] == "yes" {
            parts.append("Dog friendly.")
        }
        if let sport = tags["sport"] {
            parts.append("Sports: \(sport).")
        }

        if parts.isEmpty {
            switch category {
            case .parks: return "A local park in your area. Visit to discover what makes it special."
            case .trails: return "A trail nearby. Explore it to add it to your collection."
            case .gardens: return "A garden in your neighborhood. Worth a visit to see what's blooming."
            case .playgrounds: return "A playground nearby. Great for families and active fun."
            case .waterfront: return "A waterfront spot near you. Check it out for scenic views."
            case .sports: return "A sports facility in your area. Perfect for staying active."
            case .scenic: return "A scenic viewpoint nearby. Collect it for bonus points."
            case .community: return "A community gathering space. Connect with your neighbors here."
            }
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Additional free place sources (Recreation.gov + NPS)

    /// Recreation.gov RIDB facilities near a point (free key, true geo-radius search).
    /// Docs: https://ridb.recreation.gov/docs
    private func fetchRecreationFacilities(center: CLLocationCoordinate2D) async -> [Place] {
        let key = ProviderConfig.value("RecreationGovKey", env: "RECREATION_GOV_KEY")
        guard !key.isEmpty else { return [] }
        var comps = URLComponents(string: "https://ridb.recreation.gov/api/v1/facilities")!
        comps.queryItems = [
            .init(name: "latitude", value: "\(center.latitude)"),
            .init(name: "longitude", value: "\(center.longitude)"),
            .init(name: "radius", value: "25"),
            .init(name: "limit", value: "20")
        ]
        guard let url = comps.url, let data = await fetchJSON(url, headers: ["apikey": key]) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rec = root["RECDATA"] as? [[String: Any]] else { return [] }

        return rec.compactMap { f -> Place? in
            let name = Sanitize.text(f["FacilityName"] as? String, max: 100)
            guard !name.isEmpty else { return nil }
            let lat = (f["FacilityLatitude"] as? Double) ?? Double((f["FacilityLatitude"] as? String) ?? "") ?? 0
            let lon = (f["FacilityLongitude"] as? Double) ?? Double((f["FacilityLongitude"] as? String) ?? "") ?? 0
            guard lat != 0, lon != 0 else { return nil }
            let distMiles = Self.haversineDistance(lat1: center.latitude, lon1: center.longitude, lat2: lat, lon2: lon) / 1609.34
            let category = Self.categorizeRecreation((f["FacilityTypeDescription"] as? String ?? "") + " " + name)
            // FacilityID is numeric/opaque — keep only safe URL/ID characters.
            let rawID = (f["FacilityID"] as? String) ?? (f["FacilityID"] as? Int).map(String.init) ?? UUID().uuidString
            let id = String(rawID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" })
            let desc = Sanitize.text(f["FacilityDescription"] as? String, max: 180)
            // RIDB facilities can include a MEDIA array with real photos.
            let media = (f["MEDIA"] as? [[String: Any]])?.first { ($0["MediaType"] as? String) == "Image" }
                ?? (f["MEDIA"] as? [[String: Any]])?.first
            return Place(
                id: "rec-\(id)", name: name, category: category,
                shortDescription: desc.isEmpty ? "A federal recreation area — explore it to add it to your collection." : desc,
                distance: String(format: "%.1f mi", distMiles), distanceValue: distMiles,
                rating: nil, reviewCount: nil,   // RIDB has no ratings — never fabricate
                imagePlaceholder: category.icon, accentColor: category.tint, isFeatured: distMiles < 1.0,
                latitude: lat, longitude: lon,
                photoURL: Sanitize.url(media?["URL"] as? String)
            )
        }
    }

    /// National Park Service sites in the user's state (free key; filtered by stateCode).
    /// Docs: https://www.nps.gov/subjects/developer/api-documentation.htm
    private func fetchNPSParks(center: CLLocationCoordinate2D) async -> [Place] {
        let key = ProviderConfig.value("NpsApiKey", env: "NPS_API_KEY")
        guard !key.isEmpty, let state = await Self.reverseStateCode(center) else { return [] }
        var comps = URLComponents(string: "https://developer.nps.gov/api/v1/parks")!
        comps.queryItems = [
            .init(name: "stateCode", value: state),
            .init(name: "limit", value: "15"),
            .init(name: "api_key", value: key)
        ]
        guard let url = comps.url, let data = await fetchJSON(url) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parks = root["data"] as? [[String: Any]] else { return [] }

        return parks.compactMap { p -> Place? in
            let name = Sanitize.text(p["fullName"] as? String, max: 100)
            guard !name.isEmpty else { return nil }
            let (lat, lon) = Self.parseLatLong(p["latLong"] as? String)
            guard lat != 0 else { return nil }
            let distMiles = Self.haversineDistance(lat1: center.latitude, lon1: center.longitude, lat2: lat, lon2: lon) / 1609.34
            let rawID = (p["id"] as? String) ?? UUID().uuidString
            let id = String(rawID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" })
            let desc = Sanitize.text(p["description"] as? String, max: 180)
            // NPS returns real photography for nearly every site.
            let firstImage = (p["images"] as? [[String: Any]])?.first?["url"] as? String
            return Place(
                id: "nps-\(id)", name: name, category: .scenic,
                shortDescription: desc.isEmpty ? "A national park site — a rare find for your collection." : desc,
                distance: String(format: "%.0f mi", distMiles), distanceValue: distMiles,
                rating: nil, reviewCount: nil,   // NPS has no ratings — never fabricate
                imagePlaceholder: PlaceCategory.scenic.icon, accentColor: PlaceCategory.scenic.tint, isFeatured: false,
                latitude: lat, longitude: lon,
                photoURL: Sanitize.url(firstImage)
            )
        }
    }

    private static func categorizeRecreation(_ text: String) -> PlaceCategory {
        let t = text.lowercased()
        if t.contains("trail") { return .trails }
        if t.contains("water") || t.contains("lake") || t.contains("beach") || t.contains("marina") || t.contains("river") { return .waterfront }
        if t.contains("garden") || t.contains("botanic") { return .gardens }
        if t.contains("visitor") || t.contains("center") || t.contains("centre") { return .community }
        if t.contains("camp") || t.contains("overlook") || t.contains("scenic") { return .scenic }
        return .parks
    }

    /// Parse NPS "latLong" string: "lat:37.8651, long:-119.5383" → (37.8651, -119.5383)
    private static func parseLatLong(_ s: String?) -> (Double, Double) {
        guard let s else { return (0, 0) }
        var lat = 0.0, lon = 0.0
        for part in s.split(separator: ",") {
            let kv = part.split(separator: ":")
            guard kv.count == 2 else { continue }
            let k = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            let v = Double(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            if k == "lat" { lat = v } else if k == "long" || k == "lon" || k == "lng" { lon = v }
        }
        return (lat, lon)
    }

    /// Reverse-geocode a coordinate to a 2-letter US state code for the NPS query.
    private static func reverseStateCode(_ c: CLLocationCoordinate2D) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: c.latitude, longitude: c.longitude))
        guard let area = placemarks?.first?.administrativeArea else { return nil }
        if area.count == 2 { return area.uppercased() }
        return usStateCodes[area.lowercased()]
    }

    private static let usStateCodes: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR", "california": "CA",
        "colorado": "CO", "connecticut": "CT", "delaware": "DE", "florida": "FL", "georgia": "GA",
        "hawaii": "HI", "idaho": "ID", "illinois": "IL", "indiana": "IN", "iowa": "IA",
        "kansas": "KS", "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
        "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS", "missouri": "MO",
        "montana": "MT", "nebraska": "NE", "nevada": "NV", "new hampshire": "NH", "new jersey": "NJ",
        "new mexico": "NM", "new york": "NY", "north carolina": "NC", "north dakota": "ND", "ohio": "OH",
        "oklahoma": "OK", "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI", "south carolina": "SC",
        "south dakota": "SD", "tennessee": "TN", "texas": "TX", "utah": "UT", "vermont": "VT",
        "virginia": "VA", "washington": "WA", "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY"
    ]

    // MARK: - Collectible Building

    static func buildCollectibles(from places: [Place], center: CLLocationCoordinate2D) -> [CollectiblePlace] {
        places.map { place in
            // REAL venue coordinates whenever the source provided them — this is
            // what makes map pins and the collect-proximity check truthful.
            let coordinate: CLLocationCoordinate2D
            if let real = place.coordinate {
                coordinate = real
            } else {
                // Legacy fallback (cached places from before coords were stored):
                // deterministic ring placement at the right distance.
                let distKm = place.distanceValue * 1.60934
                let latOffset = distKm / 111.0
                let lonOffset = distKm / (111.0 * cos(center.latitude * .pi / 180))
                let angle = Double(abs(place.id.hashValue) % 360) * .pi / 180.0
                coordinate = CLLocationCoordinate2D(
                    latitude: center.latitude + latOffset * cos(angle),
                    longitude: center.longitude + lonOffset * sin(angle)
                )
            }

            return CollectiblePlace(
                id: place.id,
                place: place,
                rarity: CollectiblePlace.rarityFor(place.category),
                coordinate: coordinate
            )
        }
    }

    // MARK: - Cache (per area)

    private func cacheKeys(_ areaKey: String) -> (places: String, center: String, stamp: String) {
        ("\(Self.cachePrefix).\(areaKey).places", "\(Self.cachePrefix).\(areaKey).center", "\(Self.cachePrefix).\(areaKey).stamp")
    }

    private func persistCache(center: CLLocationCoordinate2D, areaKey: String) {
        let keys = cacheKeys(areaKey)
        let encodable = places.map { CachedPlace(from: $0) }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: keys.places)
        }
        UserDefaults.standard.set([center.latitude, center.longitude], forKey: keys.center)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: keys.stamp)
        UserDefaults.standard.set(areaKey, forKey: Self.lastAreaKey)
    }

    /// This area's cached places regardless of age (a stale cache still beats nothing when Overpass is down).
    private func cachedPlaces(areaKey: String) -> [Place]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKeys(areaKey).places),
              let cached = try? JSONDecoder().decode([CachedPlace].self, from: data) else { return nil }
        return cached.map { $0.toPlace() }
    }

    private func loadCachedPlaces(areaKey: String) {
        let keys = cacheKeys(areaKey)
        guard let cached = cachedPlaces(areaKey: areaKey),
              let centerArr = UserDefaults.standard.array(forKey: keys.center) as? [Double],
              centerArr.count == 2,
              isCacheValid(areaKey: areaKey) else { return }

        let center = CLLocationCoordinate2D(latitude: centerArr[0], longitude: centerArr[1])
        cachedCenter = center
        places = cached
        collectiblePlaces = Self.buildCollectibles(from: places, center: center)
        source = .cache
    }

    private func isCacheValid(areaKey: String) -> Bool {
        let ts = UserDefaults.standard.double(forKey: cacheKeys(areaKey).stamp)
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < cacheTTL
    }

    /// QA harness only (DEBUG + `-QAOfflineData YES`). In every other build this
    /// is a no-op and the screens render their honest empty states.
    private func useSampleFallback() {
        guard SampleData.isEnabled else { return }
        places = SampleData.places
        collectiblePlaces = SampleData.collectiblePlaces
    }

    // MARK: - Helpers

    private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB) // meters
    }

    private static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0 // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return R * c
    }
}

// MARK: - Overpass API Models

struct OverpassResponse: Decodable {
    let elements: [OSMElement]
}

struct OSMElement: Decodable {
    let type: String
    let id: Int
    let lat: Double?
    let lon: Double?
    let center: OSMCenter?
    let tags: [String: String]?
}

struct OSMCenter: Decodable {
    let lat: Double
    let lon: Double
}

// MARK: - Cache Model

private struct CachedPlace: Codable {
    let id: String
    let name: String
    let categoryRaw: String
    let shortDescription: String
    let distance: String
    let distanceValue: Double
    let rating: Double?      // optional → caches from the fabricated-rating era still decode
    let reviewCount: Int?
    let imagePlaceholder: String
    let isFeatured: Bool
    let latitude: Double?
    let longitude: Double?
    let photoURL: String?
    let openHoursReal: String?

    init(from place: Place) {
        self.id = place.id
        self.name = place.name
        self.categoryRaw = place.category.rawValue
        self.shortDescription = place.shortDescription
        self.distance = place.distance
        self.distanceValue = place.distanceValue
        self.rating = place.rating
        self.reviewCount = place.reviewCount
        self.imagePlaceholder = place.imagePlaceholder
        self.isFeatured = place.isFeatured
        self.latitude = place.latitude
        self.longitude = place.longitude
        self.photoURL = place.photoURL
        self.openHoursReal = place.openHoursReal
    }

    func toPlace() -> Place {
        let category = PlaceCategory(rawValue: categoryRaw) ?? .parks
        return Place(
            id: id,
            name: name,
            category: category,
            shortDescription: shortDescription,
            distance: distance,
            distanceValue: distanceValue,
            rating: rating,
            reviewCount: reviewCount,
            imagePlaceholder: imagePlaceholder,
            accentColor: category.tint,
            isFeatured: isFeatured,
            latitude: latitude,
            longitude: longitude,
            photoURL: photoURL,
            openHoursReal: openHoursReal
        )
    }
}

// MARK: - Errors

enum PlacesAPIError: LocalizedError {
    case invalidURL
    case serverError
    case decodingError
    /// Every Overpass mirror failed; carries the last failure for the log.
    case allMirrorsFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .serverError: return "Server returned an error"
        case .decodingError: return "Could not parse response"
        case .allMirrorsFailed(let last): return "OpenStreetMap is busy right now (\(last))"
        }
    }
}
