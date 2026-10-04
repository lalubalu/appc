import XCTest
@testable import Verdure

// MARK: - Core-logic QA: Daily Gem rotation, sanitizer, personalization mapping

@MainActor
final class CoreLogicTests: XCTestCase {

    func testParkGeometryJoinsByBoundaryAndExcludesHoles() throws {
        let json = #"{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]],[[2,2],[4,2],[4,4],[2,4],[2,2]]]}"#
        let geometry = try JSONDecoder().decode(ParkGeometry.self, from: Data(json.utf8))
        XCTAssertTrue(geometry.contains(.init(latitude: 1, longitude: 1)))
        XCTAssertFalse(geometry.contains(.init(latitude: 3, longitude: 3)))
        XCTAssertTrue(geometry.contains(.init(latitude: 3, longitude: 2)))
        XCTAssertFalse(geometry.contains(.init(latitude: 3, longitude: 11)))
        let roundTrip = try JSONDecoder().decode(ParkGeometry.self, from: JSONEncoder().encode(geometry))
        XCTAssertEqual(roundTrip.polygons, geometry.polygons)
        XCTAssertEqual(geometry.coordinatePaths.count, 2)
    }

    func testParkGeometryPreservesSeparateIslandsAndRejectsBadCoordinates() throws {
        let json = #"{"type":"MultiPolygon","coordinates":[[[[0,0],[1,0],[1,1],[0,1],[0,0]]],[[[20,20],[21,20],[21,21],[20,21],[20,20]]]]}"#
        let geometry = try JSONDecoder().decode(ParkGeometry.self, from: Data(json.utf8))
        XCTAssertTrue(geometry.contains(.init(latitude: 20.5, longitude: 20.5)))
        XCTAssertFalse(geometry.contains(.init(latitude: 15, longitude: 15)))
        for json in [#"{"type":"LineString","coordinates":[[200,1],[2,1]]}"#,
                     #"{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1]]]}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ParkGeometry.self, from: Data(json.utf8)))
        }
    }

    func testParkAmenityFiltersPersistWithoutLosingExistingChoices() throws {
        let legacy = try JSONDecoder().decode(DiscoveryFilterState.self, from: Data(#"{"radiusMiles":25,"placeCategories":["Parks"]}"#.utf8))
        XCTAssertFalse(legacy.hasParkFilters)
        XCTAssertEqual(legacy.radiusMiles, 25)
        XCTAssertEqual(legacy.placeCategories, [.parks])
        var state = legacy; state.toddlerPlayground = true; state.parkRestrooms = true
        let restored = try JSONDecoder().decode(DiscoveryFilterState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertFalse(ParkFlags(toddler: true, dogs: false, restrooms: false, water: true).matches(state))
        XCTAssertTrue(ParkFlags(toddler: true, dogs: false, restrooms: true, water: false).matches(state))
        let defaults = UserDefaults(suiteName: "park-filter-\(UUID().uuidString)")!
        let filters = DiscoveryFilters(defaults: defaults); filters.state = state
        filters.resetPlaceFilters()
        XCTAssertFalse(filters.state.hasParkFilters)
    }

    func testParkGuideLoadsRealCatalogThroughLocalCallableSDK() async throws {
        let service = ParkGuideService()
        await service.load(around: .init(latitude: 37.335, longitude: -121.89), radiusMiles: 2, force: true)
        XCTAssertNil(service.lastError)
        let park = try XCTUnwrap(service.parks.first)
        let geometry = try XCTUnwrap(park.geometry)
        XCTAssertTrue(geometry.contains(park.coordinate))
        let matches = try await service.matching(park.coordinate)
        XCTAssertTrue(matches.contains { $0.id == park.id })
        let guide = try await service.guide(id: park.id)
        XCTAssertEqual(guide.park.id, park.id)
        XCTAssertFalse(guide.credits.isEmpty)
        XCTAssertTrue(guide.credits.contains { $0.attribution.contains("City of San José") })
        XCTAssertNotNil(guide.park.geometry)
    }

    func testParkCatalogRequestSurvivesCallerNavigationCancellation() async {
        let service = ParkGuideService()
        let task = Task { await service.load(around: .init(latitude: 37.335, longitude: -121.89), radiusMiles: 2, force: true) }
        await Task.yield()
        task.cancel()
        await task.value
        XCTAssertFalse(service.isLoading)
        XCTAssertNil(service.lastError)
        XCTAssertFalse(service.parks.isEmpty)
    }

    func testSignupAgeAllowsNeutralAnswersAndKeepsMinorBoundary() {
        XCTAssertEqual(AuthService.signupAgeDecision(birthYear: nil, currentYear: 2026), .invalid)
        XCTAssertEqual(AuthService.signupAgeDecision(birthYear: 2027, currentYear: 2026), .invalid)
        XCTAssertEqual(AuthService.signupAgeDecision(birthYear: 1915, currentYear: 2026), .invalid)
        XCTAssertEqual(AuthService.signupAgeDecision(birthYear: 2026, currentYear: 2026), .under13)
        XCTAssertEqual(AuthService.signupAgeDecision(birthYear: 2014, currentYear: 2026), .under13)
        XCTAssertEqual(AuthService.signupAgeDecision(birthYear: 2013, currentYear: 2026), .eligible(2013))
        XCTAssertEqual(AuthService.signupAgeDecision(birthYear: 2009, currentYear: 2026), .eligible(2009))
        XCTAssertEqual(AuthService.signupAgeDecision(birthYear: 2008, currentYear: 2026), .eligible(2008))
    }

    func testRestoredTermsLinkResolvesAgainstExplicitLocalWebsite() async throws {
        let defaults = UserDefaults.standard
        let keys = ["QAUseFirestoreEmulator", "QAWebsiteBaseURL"]
        let before = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, before) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: "QAUseFirestoreEmulator")
        defaults.set("http://127.0.0.1:3105", forKey: "QAWebsiteBaseURL")
        XCTAssertEqual(Legal.termsOfServiceURL.absoluteString, "http://127.0.0.1:3105/terms")
        var request = URLRequest(url: Legal.termsOfServiceURL)
        request.timeoutInterval = 10
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw XCTSkip("Start the local website on port 3105 to verify the restored web Terms link: \(error.localizedDescription)") }
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Terms of Service"))
        defaults.set("https://evil.example", forKey: "QAWebsiteBaseURL")
        XCTAssertEqual(Legal.termsOfServiceURL.absoluteString, "https://verdure-app.com/terms")
        defaults.set("http://evil.127.0.0.1:3105", forKey: "QAWebsiteBaseURL")
        XCTAssertEqual(Legal.termsOfServiceURL.absoluteString, "https://verdure-app.com/terms")
        defaults.set("http://127.0.0.1:3105", forKey: "QAWebsiteBaseURL")
        defaults.set(false, forKey: "QAUseFirestoreEmulator")
        XCTAssertEqual(Legal.termsOfServiceURL.absoluteString, "https://verdure-app.com/terms")
    }

    func testUnder13SignupEndsBeforeCredentialProcessingOrPersistence() async {
        let auth = AuthService()
        let originalUser = auth.currentUser
        let keys = ["accountType", "interestCategories", "verdureUser"]
        let before = keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }
        do {
            try await auth.signUp(email: "invalid-before-age-check", password: "", displayName: "", birthYear: Calendar.current.component(.year, from: Date()) - 12,
                                  studentStatus: true, school: "Under13 fixture", interests: ["Under13 fixture"])
            XCTFail("An under-13 answer must never reach account creation")
        } catch {
            XCTAssertEqual(auth.errorMessage, "Sign-up is unavailable for this birth year.")
        }
        XCTAssertEqual(auth.currentUser?.uid, originalUser?.uid)
        XCTAssertFalse(auth.isLoading)
        XCTAssertEqual(keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }, before)
    }

    private let gemKeys = ["dailyGem.splashDay", "dailyGem.indexDay", "dailyGem.todayIndex", "dailyGem.seenIndices"]

    override func setUp() async throws {
        for key in gemKeys { UserDefaults.standard.removeObject(forKey: key) }
    }
    override func tearDown() async throws {
        for key in gemKeys { UserDefaults.standard.removeObject(forKey: key) }
    }

    // MARK: Daily Gem

    func testGemFactIsStableWithinADay() {
        let first = DailyGemStore.todaysFact
        let second = DailyGemStore.todaysFact
        XCTAssertEqual(first.id, second.id, "re-viewing today must show the same fact")
    }

    func testGemSplashShowsExactlyOncePerDay() {
        XCTAssertTrue(DailyGemStore.shouldShowSplash, "fresh day → splash due")
        DailyGemStore.markSplashShown()
        XCTAssertFalse(DailyGemStore.shouldShowSplash, "second open the same day → no splash")
    }

    func testGemNeverRepeatsUntilPoolExhausts() {
        // Simulate day-by-day selection by clearing the per-day pin while keeping
        // the seen-set, mirroring what a date change does.
        var seen = Set<String>()
        let poolSize = SampleData.gemFacts.count
        for _ in 0..<poolSize {
            let fact = DailyGemStore.todaysFact
            XCTAssertFalse(seen.contains(fact.id), "a fact repeated before the pool was exhausted")
            seen.insert(fact.id)
            UserDefaults.standard.removeObject(forKey: "dailyGem.indexDay")   // "next day"
        }
        XCTAssertEqual(seen.count, poolSize, "every fact appears exactly once per cycle")
        // Pool exhausted → recycles instead of crashing.
        XCTAssertNotNil(DailyGemStore.todaysFact)
    }

    // MARK: Sanitizer (external data is hostile)

    func testSanitizerStripsMarkupAndControlCharacters() {
        XCTAssertEqual(Sanitize.text("<b>Hello</b>\u{0007} world"), "Hello world")
        XCTAssertEqual(Sanitize.text("a &amp; b"), "a & b")
        XCTAssertEqual(Sanitize.text("  spaced   out  "), "spaced out")
        XCTAssertEqual(Sanitize.text(String(repeating: "x", count: 500), max: 10).count, 10)
    }

    func testSanitizerBlocksDangerousURLs() {
        XCTAssertNil(Sanitize.url("javascript:alert(1)"))
        XCTAssertNil(Sanitize.url("data:text/html,<script>"))
        XCTAssertNil(Sanitize.url("file:///etc/passwd"))
        XCTAssertNotNil(Sanitize.url("https://example.com/photo.jpg"))
    }

    func testSanitizerClampsCoordinates() {
        XCTAssertNil(Sanitize.latitude(91))
        XCTAssertNil(Sanitize.latitude(0), "0,0 (null island) treated as missing")
        XCTAssertEqual(Sanitize.latitude(44.98), 44.98)
        XCTAssertNil(Sanitize.longitude(181))
        XCTAssertEqual(Sanitize.coord("-93.26"), -93.26, "string coords parse")
    }

    // MARK: Personalization mapping

    func testEveryInterestMapsToAtLeastOneEventCategory() {
        for interest in PlaceCategory.allCases {
            XCTAssertFalse(interest.relatedEventCategories.isEmpty,
                           "\(interest.rawValue) must produce event recommendations")
        }
    }

    func testCommunityInterestCoversSocialEvents() {
        XCTAssertTrue(PlaceCategory.community.relatedEventCategories.contains(.social))
    }
}
