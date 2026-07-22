import XCTest
@testable import Verdure

// MARK: - Core-logic QA: Daily Gem rotation, sanitizer, personalization mapping

@MainActor
final class CoreLogicTests: XCTestCase {

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
