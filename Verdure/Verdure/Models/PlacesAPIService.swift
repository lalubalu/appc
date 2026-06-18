import Foundation
import CoreLocation
import SwiftUI
import Observation

// MARK: - Places API Service (Overpass / OpenStreetMap)

@MainActor @Observable
final class PlacesAPIService {

    // MARK: - Published State

    var places: [Place] = []
    var collectiblePlaces: [CollectiblePlace] = []
    var isLoading = false
    var lastError: String? = nil

    // MARK: - Private

    private var cachedCenter: CLLocationCoordinate2D?
    private let maxPlaces = 30
    private let radiusMeters = 5000 // 5 km search radius
    private let cacheKey = "cachedPlacesJSON"
    private let cacheCenterKey = "cachedPlacesCenter"
    private let cacheTimestampKey = "cachedPlacesTimestamp"
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    // MARK: - Init

    init() {
        loadCachedPlaces()
        if places.isEmpty {
            useSampleFallback()
        }
    }

    // MARK: - Public API

    /// Fetch nearby places from Overpass API around a coordinate.
    /// Falls back to SampleData on failure.
    func fetchNearbyPlaces(around center: CLLocationCoordinate2D) async {
        // Skip if we already fetched for a nearby coordinate recently
        if let cached = cachedCenter, isCacheValid(),
           distance(cached, center) < 500 { // within 500m of cached center
            return
        }

        isLoading = true
        lastError = nil

        do {
            let osmElements = try await queryOverpass(center: center)
            let mapped = mapToPlaces(osmElements, center: center)

            self.places = mapped
            self.collectiblePlaces = Self.buildCollectibles(from: mapped, center: center)
            self.cachedCenter = center
            self.isLoading = false
            self.persistCache(center: center)
        } catch {
            self.lastError = error.localizedDescription
            self.isLoading = false
            // Keep existing data if we have it, otherwise fall back
            if self.places.isEmpty {
                self.useSampleFallback()
            }
        }
    }

    /// Find the CollectiblePlace wrapper for a given Place
    func collectible(for place: Place) -> CollectiblePlace? {
        collectiblePlaces.first { $0.place.id == place.id }
    }

    // MARK: - Overpass Query

    private func queryOverpass(center: CLLocationCoordinate2D) async throws -> [OSMElement] {
        let lat = center.latitude
        let lon = center.longitude
        let r = radiusMeters

        // Query parks, trails, gardens, playgrounds, waterfront, sports, scenic, community spaces
        let query = """
        [out:json][timeout:15];
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
        out center body qt \(maxPlaces * 2);
        """

        let urlString = "https://overpass-api.de/api/interpreter"
        guard let url = URL(string: urlString) else {
            throw PlacesAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query)".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlacesAPIError.serverError
        }

        let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
        return decoded.elements
    }

    // MARK: - Mapping OSM -> Place

    private func mapToPlaces(_ elements: [OSMElement], center: CLLocationCoordinate2D) -> [Place] {
        var seen = Set<String>() // deduplicate by name
        var results: [Place] = []

        for element in elements {
            guard let name = element.tags?["name"], !name.isEmpty else { continue }

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

            let place = Place(
                id: "osm-\(element.id)",
                name: name,
                category: category,
                shortDescription: Self.buildDescription(tags: element.tags ?? [:], category: category, name: name),
                distance: String(format: "%.1f mi", distMiles),
                distanceValue: distMiles,
                rating: Self.syntheticRating(tags: element.tags ?? [:]),
                reviewCount: Int.random(in: 12...200),
                imagePlaceholder: category.icon,
                accentColor: category.tint,
                isFeatured: distMiles < 0.5
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

    private static func syntheticRating(tags: [String: String]) -> Double {
        // Better-tagged places tend to be more notable
        var base = 4.0
        if tags["wikipedia"] != nil { base += 0.5 }
        if tags["wheelchair"] == "yes" { base += 0.2 }
        if tags["website"] != nil { base += 0.1 }
        return min(base + Double.random(in: -0.3...0.3), 5.0)
    }

    // MARK: - Collectible Building

    static func buildCollectibles(from places: [Place], center: CLLocationCoordinate2D) -> [CollectiblePlace] {
        places.map { place in
            // Parse distance back to coordinate offset (approximate)
            let distMiles = place.distanceValue
            let distKm = distMiles * 1.60934
            let latOffset = distKm / 111.0  // rough deg per km
            let lonOffset = distKm / (111.0 * cos(center.latitude * .pi / 180))

            // Distribute around center using place ID hash for deterministic placement
            let hash = abs(place.id.hashValue)
            let angle = Double(hash % 360) * .pi / 180.0
            let coordLat = center.latitude + latOffset * cos(angle)
            let coordLon = center.longitude + lonOffset * sin(angle)

            return CollectiblePlace(
                id: place.id,
                place: place,
                rarity: CollectiblePlace.rarityFor(place.category),
                coordinate: CLLocationCoordinate2D(latitude: coordLat, longitude: coordLon)
            )
        }
    }

    // MARK: - Cache

    private func persistCache(center: CLLocationCoordinate2D) {
        let encodable = places.map { CachedPlace(from: $0) }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        UserDefaults.standard.set([center.latitude, center.longitude], forKey: cacheCenterKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
    }

    private func loadCachedPlaces() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CachedPlace].self, from: data),
              let centerArr = UserDefaults.standard.array(forKey: cacheCenterKey) as? [Double],
              centerArr.count == 2,
              isCacheValid() else { return }

        let center = CLLocationCoordinate2D(latitude: centerArr[0], longitude: centerArr[1])
        cachedCenter = center
        places = cached.map { $0.toPlace() }
        collectiblePlaces = Self.buildCollectibles(from: places, center: center)
    }

    private func isCacheValid() -> Bool {
        let ts = UserDefaults.standard.double(forKey: cacheTimestampKey)
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < cacheTTL
    }

    private func useSampleFallback() {
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

private struct OverpassResponse: Decodable {
    let elements: [OSMElement]
}

private struct OSMElement: Decodable {
    let type: String
    let id: Int
    let lat: Double?
    let lon: Double?
    let center: OSMCenter?
    let tags: [String: String]?
}

private struct OSMCenter: Decodable {
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
    let rating: Double
    let reviewCount: Int
    let imagePlaceholder: String
    let isFeatured: Bool

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
            isFeatured: isFeatured
        )
    }
}

// MARK: - Errors

enum PlacesAPIError: LocalizedError {
    case invalidURL
    case serverError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .serverError: return "Server returned an error"
        case .decodingError: return "Could not parse response"
        }
    }
}
