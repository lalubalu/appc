import XCTest
import CoreLocation
@testable import Verdure

/// CAC 2026 (1.4): Overpass mirror fallback, the per-area cache and the bundled
/// OpenStreetMap snapshot. The transport is injected, so no test reaches the
/// internet; each answer below is a fixture.
@MainActor
final class PlacesMirrorTests: XCTestCase {
    private let sanJose = CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863)

    private static let overpassJSON = """
    {"version":0.6,"generator":"test","elements":[
      {"type":"node","id":1,"lat":37.3395,"lon":-121.8900,"tags":{"leisure":"park","name":"Fixture Park","opening_hours":"sunrise-sunset"}},
      {"type":"way","id":2,"center":{"lat":37.3360,"lon":-121.8840},"tags":{"highway":"path","name":"Fixture Trail"}},
      {"type":"node","id":3,"lat":37.3410,"lon":-121.8850,"tags":{"leisure":"garden","name":"Fixture Garden"}}
    ]}
    """.data(using: .utf8)!

    private func http(_ request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func clearCaches() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("cachedPlaces.v3") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func setUp() { super.setUp(); clearCaches() }
    override func tearDown() { clearCaches(); super.tearDown() }

    func testEveryRequestIdentifiesTheAppAndCarriesTheMirrorTimeout() async {
        let seen = Recorder()
        let service = PlacesAPIService(transport: { request in
            seen.append(request)
            return (Self.overpassJSON, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, snapshot: nil)
        await service.fetchNearbyPlaces(around: sanJose)
        let requests = seen.requests
        XCTAssertEqual(requests.count, 1, "the first mirror answered, so no other mirror is asked")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "User-Agent"), "Verdure/1.0 (+https://verdure-app.com)")
        XCTAssertFalse(requests.first?.value(forHTTPHeaderField: "User-Agent")?.contains("@") ?? true, "no personal address in the agent")
        XCTAssertEqual(requests.first?.timeoutInterval, 25)
        XCTAssertEqual(service.source, .live(mirror: "overpass-api.de"))
        XCTAssertEqual(service.places.map(\.name).sorted(), ["Fixture Garden", "Fixture Park", "Fixture Trail"])
        XCTAssertNil(service.snapshotDate, "a live answer shows no snapshot date")
    }

    func testFallsThroughTheMirrorsInOrderUntilOneAnswers() async {
        let seen = Recorder()
        let service = PlacesAPIService(transport: { request in
            seen.append(request)
            switch request.url!.host {
            case "overpass-api.de": return (Data("busy".utf8), HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!)
            case "overpass.private.coffee": throw URLError(.timedOut)
            default: return (Self.overpassJSON, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }, snapshot: nil)
        await service.fetchNearbyPlaces(around: sanJose)
        XCTAssertEqual(seen.requests.map { $0.url!.host! }, ["overpass-api.de", "overpass.private.coffee", "overpass.kumi.systems"])
        XCTAssertEqual(service.source, .live(mirror: "overpass.kumi.systems"))
        XCTAssertEqual(service.places.count, 3)
        XCTAssertNil(service.lastError)
    }

    func testAllMirrorsDownUsesTheBundledSnapshotAndShowsItsDate() async throws {
        let snapshotJSON = """
        {"center":{"lat":37.3382,"lon":-121.8863},"radiusMeters":5000,"fetchedAt":"2026-10-25T03:00:00Z",
         "endpoint":"https://overpass-api.de/api/interpreter","attribution":"© OpenStreetMap contributors (ODbL)",
         "elements":[{"type":"node","id":9,"lat":37.3400,"lon":-121.8870,"tags":{"leisure":"park","name":"Snapshot Park"}},
                     {"type":"node","id":10,"lat":37.3420,"lon":-121.8890,"tags":{"leisure":"playground","name":"Snapshot Playground"}}]}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(OSMSnapshot.self, from: snapshotJSON)
        let seen = Recorder()
        let service = PlacesAPIService(transport: { request in seen.append(request); throw URLError(.cannotConnectToHost) }, snapshot: snapshot)
        await service.fetchNearbyPlaces(around: sanJose)
        XCTAssertEqual(seen.requests.count, PlacesAPIService.overpassMirrors.count, "every mirror is tried before giving up")
        XCTAssertEqual(service.source, .snapshot(date: "2026-10-25"))
        XCTAssertEqual(service.snapshotDate, "2026-10-25")
        XCTAssertEqual(service.places.map(\.name).sorted(), ["Snapshot Park", "Snapshot Playground"])
        XCTAssertTrue(service.places.allSatisfy { $0.id.hasPrefix("osm-") }, "snapshot places carry the osm- prefix so the credit shows")
        XCTAssertNotNil(service.lastError, "the failure is recorded, not hidden")
    }

    func testSnapshotIsNotUsedFarFromWhereItWasCaptured() async throws {
        let snapshot = try JSONDecoder().decode(OSMSnapshot.self, from: """
        {"center":{"lat":37.3382,"lon":-121.8863},"radiusMeters":5000,"fetchedAt":"2026-10-25T03:00:00Z","endpoint":"x","attribution":"x",
         "elements":[{"type":"node","id":9,"lat":37.34,"lon":-121.887,"tags":{"leisure":"park","name":"Snapshot Park"}}]}
        """.data(using: .utf8)!)
        let service = PlacesAPIService(transport: { _ in throw URLError(.cannotConnectToHost) }, snapshot: snapshot)
        await service.fetchNearbyPlaces(around: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060))   // New York
        XCTAssertFalse(service.places.contains { $0.name == "Snapshot Park" }, "San José places are never shown in New York")
        XCTAssertNotEqual(service.source, .snapshot(date: "2026-10-25"))
    }

    func testPerAreaCacheIsServedOnlyForItsOwnArea() async {
        let seen = Recorder()
        let service = PlacesAPIService(transport: { request in
            seen.append(request)
            if seen.requests.count == 1 { return (Self.overpassJSON, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
            throw URLError(.cannotConnectToHost)
        }, snapshot: nil)
        await service.fetchNearbyPlaces(around: sanJose)                       // live, cached under San José's cell
        XCTAssertEqual(service.source, .live(mirror: "overpass-api.de"))
        let paloAlto = CLLocationCoordinate2D(latitude: 37.4419, longitude: -122.1430)
        await service.fetchNearbyPlaces(around: paloAlto)                      // every mirror down, no cache for this cell, no snapshot
        XCTAssertNotEqual(service.source, .cache, "San José's cache is not served in Palo Alto")
        XCTAssertNotEqual(PlacesAPIService.areaKey(sanJose), PlacesAPIService.areaKey(paloAlto))
        // Back in San José with Overpass still down: this area's cache answers.
        let fresh = PlacesAPIService(transport: { _ in throw URLError(.cannotConnectToHost) }, snapshot: nil)
        await fresh.fetchNearbyPlaces(around: CLLocationCoordinate2D(latitude: 37.3450, longitude: -121.8900))   // 1 km away, same cell
        XCTAssertEqual(fresh.source, .cache)
        XCTAssertEqual(fresh.places.count, 3)
    }

    func testBundledSnapshotCoversTheLaunchAreaWhenPresent() throws {
        // The snapshot file ships only once Overpass has answered for a capture
        // (functions/scripts/osm-snapshot.mjs). When it is in the bundle it must
        // be the launch-area query, with the attribution and a capture date.
        guard let snapshot = OSMSnapshot.bundled() else {
            XCTFail("Resources/osm-snapshot-san-jose.json is missing from the bundle — capture it with functions/scripts/osm-snapshot.mjs")
            return
        }
        XCTAssertTrue(snapshot.covers(sanJose))
        XCTAssertGreaterThanOrEqual(snapshot.elements.count, 10)
        XCTAssertTrue(snapshot.attribution.contains("OpenStreetMap"))
        XCTAssertEqual(snapshot.dateLabel.count, 10)
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [URLRequest] = []
        func append(_ r: URLRequest) { lock.lock(); items.append(r); lock.unlock() }
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return items }
    }
}
