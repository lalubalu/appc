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

    /// This used to assert a Verdure+ lock chip on the "Gold tier".
    ///
    /// That tier no longer exists. amazon-25, nike-25, apple-50 and rei-50 are
    /// all `active: false` in CASH_CATALOG — the server refuses every one of
    /// them — so they were removed from the client catalog rather than shown as
    /// a locked upsell for something nobody can ever buy. The test now asserts
    /// the contract that replaced it: cash is members-only, and NOTHING the
    /// server has deactivated appears on this screen or on the paywall.
    func testRewardsGatesCashBehindPaywallAndSellsOnlyLiveFeatures() {
        let app = QA.launch(tab: "profile")
        QA.waitFor(app.buttons["Rewards"].firstMatch, "rewards button").tap()
        QA.waitFor(app.staticTexts["AVAILABLE POINTS"], "rewards store")

        app.swipeUp(); app.swipeUp()

        // No deactivated tier may be browsable. These were redeemable-looking
        // and permanently un-redeemable, which is the defect A1 fixed.
        for dead in ["$25 Amazon", "$50 Apple", "$25 Nike", "$50 REI"] {
            XCTAssertFalse(app.staticTexts[dead].exists,
                           "\(dead) is active:false on the server and must not be shown")
        }

        // Cash is a member benefit; the lock is on the cash section.
        let lock = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'requires Verdure Plus'")).firstMatch
        guard lock.waitForExistence(timeout: 6) else {
            // A non-member with no cash rewards loaded is a legitimate state
            // (the catalog is server-driven). Say which, rather than failing
            // on an assumption about what the server returned.
            XCTAssertTrue(app.staticTexts["Partner Perks"].exists
                          || app.staticTexts["Gift Cards"].exists,
                          "rewards store rendered neither perks nor cash")
            return
        }
        lock.tap()

        QA.waitFor(app.buttons["Start Verdure Plus"], "paywall CTA from rewards lock")

        // Honest-copy check, updated for A2: the paywall leads with the planner
        // and must never again name a deactivated reward tier.
        XCTAssertTrue(app.staticTexts["Unlimited Adventure Planner"].exists,
                      "the paywall should lead with the benefit a member uses on day one")
        XCTAssertFalse(app.staticTexts["Premium Rewards"].exists,
                       "the old Gold/Platinum pitch must be gone")
        for dead in ["$25", "$50"] {
            XCTAssertFalse(app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", dead)).element.exists,
                "the paywall must not advertise a deactivated tier (\(dead))")
        }
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
