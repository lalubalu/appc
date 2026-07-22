import XCTest

// MARK: - Core user-journey smoke tests
//
// Deterministic flows only (state injected via launch arguments; no dependence
// on which live events happen to load — sample fallback guarantees content).

@MainActor
final class JourneyTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Tabs

    func testAllTabsRender() {
        let anchors: [(tab: String, text: String)] = [
            ("events", "Events"), ("explore", "Explore"), ("map", "Map"),
            ("collect", "Collect"), ("community", "Community"), ("profile", "PLAYER CARD"),
        ]
        for (tab, anchor) in anchors {
            let app = QA.launch(tab: tab)
            QA.waitFor(app.staticTexts[anchor].firstMatch, "\(tab) tab anchor")
            app.terminate()
        }
    }

    // MARK: Event detail + check-in gate

    func testEventDetailShowsProofRequirement() {
        let app = QA.launch(tab: "events")
        // The poster deck's paged scroll-transition churns element identity under
        // XCUITest (exists at wait-time, gone at tap-time) — use the stable
        // timeline rows below instead; they open the same detail sheet.
        app.swipeUp(); app.swipeUp()
        let row = QA.waitFor(app.descendants(matching: .any)
            .matching(identifier: "event-row-0").firstMatch, "first timeline event row")
        let detailAnchor = app.buttons["Get Directions"]
        row.tap()
        if !detailAnchor.waitForExistence(timeout: 6) {
            row.tap()   // retry once if the tap raced the scroll settle
        }
        QA.waitFor(detailAnchor, "event detail sheet")
        // Every un-attended event demands proof of attendance before check-in.
        let upload = app.buttons["Upload Proof of Attendance"]
        let checkedIn = app.staticTexts["Checked In"]
        XCTAssertTrue(upload.waitForExistence(timeout: 6) || checkedIn.waitForExistence(timeout: 2),
                      "event detail must show the proof requirement (or an attended state)")
        // The old decorative promise is now backed by a real gate.
        XCTAssertTrue(app.staticTexts["Be within 500 ft and upload proof of attendance to check in."].exists
                      || checkedIn.exists)
    }

    // MARK: Rewards gating + paywall

    func testRewardsLocksGoldTierBehindPaywall() {
        let app = QA.launch(tab: "profile")
        QA.waitFor(app.buttons["Rewards"].firstMatch, "rewards button").tap()
        QA.waitFor(app.staticTexts["AVAILABLE POINTS"], "rewards store")

        app.swipeUp(); app.swipeUp()
        let lockChip = QA.waitFor(
            app.buttons["Gold tier requires Verdure Plus"].firstMatch,
            "Verdure+ lock chip on Gold tier")
        lockChip.tap()

        QA.waitFor(app.buttons["Start Verdure Plus"], "paywall CTA from rewards lock")
        // Honest-copy check: the sheet only sells live features.
        XCTAssertTrue(app.staticTexts["Premium Rewards"].exists)
        XCTAssertFalse(app.staticTexts["AI Adventure Planner"].exists,
                       "unshipped features must not be sold on the paywall")
    }

    // MARK: Personalization

    func testInterestTuningFlow() {
        let app = QA.launch(tab: "events")
        QA.waitFor(app.buttons["Tune recommendations"].firstMatch, "tune button").tap()
        QA.waitFor(app.staticTexts["Your Interests"], "interest picker")
        app.buttons["Gardens"].firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
        QA.waitFor(app.staticTexts["Events"].firstMatch, "back on events")
    }

    // MARK: Daily Gem

    func testDailyGemRevealFromExplore() {
        let app = QA.launch(tab: "explore")
        let tile = QA.waitFor(app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH 'Today\\'s Gem'")).firstMatch, "gem tile")
        tile.tap()
        let gem = QA.waitFor(app.staticTexts["Daily Gem"], "gem splash title")
        _ = gem
        app.buttons["Daily Gem"].firstMatch.tap()   // reveal (the gem exposes .isButton)
        QA.waitFor(app.staticTexts["Tap anywhere to continue"], "revealed fact")
        app.staticTexts["Tap anywhere to continue"].tap() // dismiss
        QA.waitFor(app.staticTexts["Explore"].firstMatch, "back on explore")
    }

    // MARK: Daily Gem once-per-day (fresh day → splash auto-shows)

    func testDailyGemAutoShowsOnFirstOpenOfDay() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            "-dailyGem.splashDay", "2000-01-01",   // long ago → splash due
            "-QATab", "events",
        ]
        app.launch()
        QA.waitFor(app.staticTexts["Daily Gem"], "auto splash on a new day")
    }

    // MARK: Community

    func testCommunityComposeSheetOpens() {
        let app = QA.launch(tab: "community")
        QA.waitFor(app.buttons["New post"].firstMatch, "compose FAB").tap()
        QA.waitFor(app.staticTexts["New Post"], "compose sheet")
        app.buttons["Cancel"].firstMatch.tap()
    }

    // MARK: Onboarding

    func testOnboardingWalkthroughToAuth() {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "NO", "-QADisableMotion", "YES"]
        app.launch()

        QA.waitFor(app.staticTexts["Step Outside.\nConnect Within."], "page 1")
        app.buttons["Continue"].tap()
        QA.waitFor(app.staticTexts["Earn Rewards\nFor Exploring"], "page 2")
        app.buttons["Continue"].tap()
        QA.waitFor(app.staticTexts["Build Real\nConnections"], "page 3")
        app.buttons["Continue"].tap()

        QA.waitFor(app.staticTexts["What draws you\noutdoors?"], "interests page")
        app.buttons["Parks interest"].firstMatch.tap()
        QA.waitFor(app.buttons["Continue · 1 picked"], "selection reflected in CTA").tap()

        // Onboarding hands off to AuthView (defaults to Sign In mode).
        QA.waitFor(app.buttons["Continue as guest"].firstMatch, "auth page")
    }
}
