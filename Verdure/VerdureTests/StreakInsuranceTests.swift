import XCTest
@testable import Verdure

// MARK: - Streak insurance (G2)
//
// Before this, one missed day reset a 40-day streak to 1 — a punishment for
// having a life, landing hardest on the users with the most invested. These
// tests pin the forgiveness AND its limits, because "insurance" that quietly
// forgives everything is just a streak that never breaks, which means nothing.

@MainActor
final class StreakInsuranceTests: XCTestCase {

    private var state: GameStateManager!

    override func setUp() async throws {
        for key in ["streakCount", "streakLastDay", "streakInsuranceUsedOn"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        state = GameStateManager()
    }

    private func day(_ n: Int) -> Date {
        // Fixed anchor so nothing here depends on when the suite runs.
        Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(Double(n) * 86_400)
    }

    func testConsecutiveDaysBuildAStreak() {
        state.recordActiveDay(now: day(0))
        XCTAssertEqual(state.currentStreak, 1)
        state.recordActiveDay(now: day(1))
        state.recordActiveDay(now: day(2))
        XCTAssertEqual(state.currentStreak, 3)
    }

    func testSameDayIsANoOp() {
        state.recordActiveDay(now: day(0))
        state.recordActiveDay(now: day(0))
        state.recordActiveDay(now: day(0))
        XCTAssertEqual(state.currentStreak, 1, "opening the app twice is not two days")
    }

    // MARK: The forgiveness

    func testOneMissedDayIsForgiven() {
        state.recordActiveDay(now: day(0))
        state.recordActiveDay(now: day(1))
        state.recordActiveDay(now: day(2))
        XCTAssertEqual(state.currentStreak, 3)

        // Skips day 3 entirely, returns on day 4.
        let used = state.recordActiveDay(now: day(4))
        XCTAssertTrue(used, "the gap was covered by insurance")
        XCTAssertEqual(state.currentStreak, 4, "the streak survives and counts today")
    }

    func testTwoMissedDaysAreNotForgiven() {
        state.recordActiveDay(now: day(0))
        state.recordActiveDay(now: day(1))
        XCTAssertEqual(state.currentStreak, 2)

        let used = state.recordActiveDay(now: day(5))   // three days missed
        XCTAssertFalse(used)
        XCTAssertEqual(state.currentStreak, 1, "a real lapse still resets")
    }

    // MARK: The limit — this is what stops it becoming an unbreakable streak

    func testInsuranceCannotBeUsedTwiceInTheWindow() {
        state.recordActiveDay(now: day(0))
        state.recordActiveDay(now: day(2))               // first gap, forgiven
        XCTAssertEqual(state.currentStreak, 2)
        XCTAssertFalse(state.streakInsuranceAvailable(now: day(2)))

        let used = state.recordActiveDay(now: day(4))    // second gap, same window
        XCTAssertFalse(used, "only one forgiven day per 30")
        XCTAssertEqual(state.currentStreak, 1)
    }

    func testInsuranceRechargesAfterTheWindow() {
        state.recordActiveDay(now: day(0))
        state.recordActiveDay(now: day(2))               // uses insurance
        XCTAssertFalse(state.streakInsuranceAvailable(now: day(10)))
        XCTAssertTrue(state.streakInsuranceAvailable(now: day(32)),
                      "available again after the 30-day window")
    }

    func testInsuranceIsAvailableToABrandNewAccount() {
        XCTAssertTrue(state.streakInsuranceAvailable(now: day(0)),
                      "a new user has not spent anything")
    }

    // MARK: It is not a paid benefit

    func testInsuranceIsNotGatedOnMembership() {
        // Deliberate product decision, asserted so it can't drift into the
        // paywall later: selling relief from a punishment we invented would
        // make the streak a lever on the subscription.
        state.recordActiveDay(now: day(0))
        let used = state.recordActiveDay(now: day(2))
        XCTAssertTrue(used, "forgiveness applies without any subscription check")
        XCTAssertEqual(GameStateManager.streakInsuranceDays, 1)
        XCTAssertEqual(GameStateManager.streakInsuranceWindowDays, 30)
    }
}
