import XCTest
import CryptoKit
@preconcurrency import FirebaseAuth
@testable import Verdure

// MARK: - Core-logic QA: Daily Gem rotation, sanitizer, personalization mapping

@MainActor
final class CoreLogicTests: XCTestCase {

    func testOfflinePackActualSDKDownloadPersistenceIsolationAndDeletion() async throws {
        let auth = Auth.auth()
        try await auth.signIn(withEmail: "offline-native-plus@example.test", password: "local-offline-native-only")
        defer { NetworkStatus.shared.forceOfflineForTesting = false; NetworkStatus.shared.forceWiFiForTesting = false; try? auth.signOut() }
        for _ in 0..<50 where !NetworkStatus.shared.isOnline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(NetworkStatus.shared.isOnline)
        let uid = try XCTUnwrap(auth.currentUser?.uid)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("offline-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = OfflinePackService(directory: directory); service.connect(uid)
        let preview = try await service.preview(selection: .parks(["county-boundaries_20"]), places: [], savedPlaceIDs: [])
        XCTAssertGreaterThan(preview.downloadBytes, preview.storedBytes)
        XCTAssertLessThanOrEqual(preview.downloadBytes, OfflinePackService.maxBytes)
        XCTAssertEqual(preview.expiresAtMs - preview.createdAtMs, 604_800_000)
        XCTAssertTrue(service.entries.isEmpty, "Size preview must not install a pack")
        try await service.download(preview)
        let entry = try XCTUnwrap(service.entries.first)
        let pack = try service.open(entry)
        XCTAssertEqual(pack.guides.count, 1); XCTAssertFalse(pack.guides[0].trails.isEmpty)
        XCTAssertNotNil(pack.guides[0].park.geometry); XCTAssertFalse(pack.guides[0].credits.isEmpty)
        XCTAssertFalse(pack.mapImageryIncluded); XCTAssertFalse(pack.checkInAllowed)
        // UI preflight forced offline. Opening uses only the checked local file;
        // actual cellular/GPS/airplane-mode testing is still a physical gate.
        NetworkStatus.shared.forceOfflineForTesting = true
        let restored = OfflinePackService(directory: directory); restored.connect(uid)
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertEqual(try restored.open(entry).guides[0].trails.count, pack.guides[0].trails.count)
        do { _ = try await restored.preview(selection: entry.selection, places: [], savedPlaceIDs: []); XCTFail("Offline generation must be refused") }
        catch { XCTAssertEqual(error.localizedDescription, "Available when you're back online.") }
        let accountDirectory = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try accountDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let bytes = try JSONEncoder().encode(pack)
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        XCTAssertThrowsError(try OfflinePackService.verifiedPack(bytes, sha256: "damaged", ownerUid: uid))
        XCTAssertThrowsError(try OfflinePackService.verifiedPack(bytes, sha256: hash(bytes), ownerUid: "another-account"))
        XCTAssertThrowsError(try OfflinePackService.verifiedPack(bytes, sha256: hash(bytes), ownerUid: uid, nowMs: pack.expiresAtMs))
        for patch in [["checkInAllowed": true], ["mapImageryIncluded": true], ["version": 2], ["expiresAtMs": pack.createdAtMs + 604_800_001]] as [[String: Any]] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            object.merge(patch) { _, new in new }
            let changed = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try OfflinePackService.verifiedPack(changed, sha256: hash(changed), ownerUid: uid))
        }
        try restored.delete(entry)
        XCTAssertTrue(restored.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountDirectory.appendingPathComponent(entry.id + ".json").path))
        restored.connect("another-account")
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountDirectory.path))
        XCTAssertThrowsError(try restored.open(entry))
    }

    func testOfflinePackWiFiRefreshReplacesOnlyACompleteDownloadAndKeepsPlaces() async throws {
        let auth = Auth.auth()
        try await auth.signIn(withEmail: "offline-native-plus@example.test", password: "local-offline-native-only")
        defer { NetworkStatus.shared.forceOfflineForTesting = false; NetworkStatus.shared.forceWiFiForTesting = false; try? auth.signOut() }
        for _ in 0..<50 where !NetworkStatus.shared.isOnline { try await Task.sleep(for: .milliseconds(100)) }
        let uid = try XCTUnwrap(auth.currentUser?.uid)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = OfflinePackService(directory: directory); service.connect(uid)
        let guide = try await ParkGuideService().guide(id: "county-boundaries_20")
        let point = guide.park.coordinate
        let place = Place(id: "osm-local-offline-fixture", name: "Fictional cached provider place", category: .parks,
                          shortDescription: "Local fixture", distance: "", distanceValue: 0, rating: nil, reviewCount: nil,
                          imagePlaceholder: "leaf.fill", accentColor: .verdureGreen, isFeatured: false, latitude: point.latitude, longitude: point.longitude)
        let preview = try await service.preview(selection: .parks([guide.park.id]), places: [place], savedPlaceIDs: [place.id])
        try await service.download(preview)
        let first = try XCTUnwrap(service.entries.first)
        XCTAssertEqual(try service.open(first).places.count, 1)
        NetworkStatus.shared.forceOfflineForTesting = true
        await service.refreshOnWiFi(places: [], savedPlaceIDs: [place.id])
        XCTAssertEqual(service.entries.first?.id, first.id, "Offline refresh must keep the current complete pack")
        NetworkStatus.shared.forceOfflineForTesting = false; NetworkStatus.shared.forceWiFiForTesting = true
        await service.refreshOnWiFi(places: [], savedPlaceIDs: [place.id])
        XCTAssertNil(service.lastError)
        let updated = try XCTUnwrap(service.entries.first)
        XCTAssertNotEqual(updated.id, first.id)
        XCTAssertEqual(service.entries.count, 1)
        let fresh = try service.open(updated)
        XCTAssertEqual(fresh.places.first?.id, place.id); XCTAssertEqual(fresh.places.first?.saved, true)
        XCTAssertTrue(fresh.places.first?.attribution.contains("OpenStreetMap") == true)
        XCTAssertThrowsError(try service.open(first), "Old file must be deleted only after a complete replacement")
        await service.refreshOnWiFi(places: [], savedPlaceIDs: [])
        XCTAssertEqual(service.entries.first?.id, updated.id, "Repeated foregrounds must respect the hourly refresh bound")
    }

    func testOfflinePackFreeAccountRefusedByActualSDKAndActionsDoNotMutate() async throws {
        let auth = Auth.auth()
        try await auth.signIn(withEmail: "offline-native-free@example.test", password: "local-offline-native-only")
        defer { NetworkStatus.shared.forceOfflineForTesting = false; try? auth.signOut() }
        for _ in 0..<50 where !NetworkStatus.shared.isOnline { try await Task.sleep(for: .milliseconds(100)) }
        let service = OfflinePackService(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        service.connect(auth.currentUser?.uid)
        do { _ = try await service.preview(selection: .parks(["city-parks_342"]), places: [], savedPlaceIDs: []); XCTFail("Free account must be refused by server") }
        catch { XCTAssertEqual((error as NSError).code, 7, "Firebase permission denied") }
        XCTAssertTrue(service.entries.isEmpty)
        NetworkStatus.shared.forceOfflineForTesting = true
        let social = SocialService()
        let going = await social.setGoing("never-submit-offline", going: true)
        XCTAssertFalse(going)
        XCTAssertFalse(social.isGoing("never-submit-offline"))
        XCTAssertEqual(social.lastError, "Available when you're back online.")
        do { _ = try await AdventurePlannerService().plan(places: [], interests: [], timeOfDay: "morning", durationMinutes: 60, latitude: 37, longitude: -121); XCTFail("Offline planning must be refused") }
        catch { XCTAssertEqual(error.localizedDescription, "Plan generation is available when you're back online.") }
    }

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
