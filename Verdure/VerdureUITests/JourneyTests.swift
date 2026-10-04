import XCTest

// MARK: - Core user-journey smoke tests
//
// Deterministic flows only (state injected via launch arguments; no dependence
// on which live events happen to load — sample fallback guarantees content).

@MainActor
final class JourneyTests: XCTestCase {
    func testCuratedProgramActualSignInChipAndOfficialListingDetail() throws {
        var app = QA.launch(tab: "profile", extraArguments: ["-QAOfflineData", "NO", "-QAUseFirestoreEmulator", "YES", "-QAResetAuth", "YES"])
        let signIn = app.buttons["profileSignIn"]
        for _ in 0..<20 where !signIn.isHittable { app.swipeUp() }
        QA.waitFor(signIn, "guest sign-in entry").tap()
        let email = QA.waitFor(app.textFields["Email address"], "email field")
        email.tap(); email.typeText("program-native-adult@example.test")
        let password = app.secureTextFields["Password"]
        password.tap(); password.typeText("local-program-native-only")
        let submit = app.buttons["authSubmit"]
        for _ in 0..<4 where !submit.isHittable { app.swipeUp() }
        QA.waitFor(submit, "sign-in submission").tap()
        QA.waitFor(app.buttons["openOfflinePacks"], "signed-in profile", timeout: 30)
        app.terminate()
        app = QA.launch(tab: "events", extraArguments: ["-QAOfflineData", "NO", "-QAUseFirestoreEmulator", "YES"])
        let filterButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Filters")).firstMatch
        QA.waitFor(filterButton, "event filters", timeout: 30).tap()
        QA.waitFor(app.buttons["50 mi"], "explicit browsing radius").tap()
        app.buttons["Done"].tap()
        let program = app.buttons["event-category:Program"]
        let categories = app.scrollViews["eventCategories"]
        for _ in 0..<10 where !categories.isHittable { app.swipeUp() }
        QA.waitFor(categories, "category shortcuts", timeout: 30)
        for _ in 0..<4 { categories.swipeLeft() }
        let visible = program.waitForExistence(timeout: 30)
        if !visible {
            let failure = XCTAttachment(screenshot: app.screenshot()); failure.name = "Program chip failure"; failure.lifetime = .keepAlways; add(failure)
            print(app.debugDescription.prefix(8000))
        }
        XCTAssertTrue(visible, "ten current Programs enable the chip")
        guard visible else { return }
        program.tap()
        let card = app.buttons.matching(identifier: "event-poster").matching(NSPredicate(format: "label BEGINSWITH %@", "Fictional native program 0, Program")).firstMatch
        QA.waitFor(card, "actual curated Program poster", timeout: 30)
        // Bring the poster above the persistent tab bar before tapping it.
        for _ in 0..<8 {
            let centerY = card.frame.midY
            if centerY > 240 && centerY < app.frame.height - 160 { break }
            if centerY >= app.frame.height - 160 { app.swipeUp() } else { app.swipeDown() }
        }
        card.tap()
        let opened = XCTAttachment(screenshot: app.screenshot()); opened.name = "Program after card tap"; opened.lifetime = .keepAlways; add(opened)
        let official = app.buttons["programOfficialListing"]
        for _ in 0..<4 where !official.isHittable { app.swipeUp() }
        if !official.exists { print(app.debugDescription.prefix(12000)) }
        QA.waitFor(official, "official listing link")
        XCTAssertFalse(app.buttons["Upload Proof of Attendance"].exists)
        XCTAssertFalse(app.buttons["Get Directions"].exists)
        XCTAssertFalse(app.buttons["Going"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Curated Program detail"; shot.lifetime = .keepAlways; add(shot)
        try QA.audit(app, screen: "Curated Program detail")
    }

    func testOfflinePackSignInSizeDownloadRelaunchAndStoredTrailView() throws {
        var app = QA.launch(tab: "profile", extraArguments: ["-QAOfflineData", "NO", "-QAUseFirestoreEmulator", "YES", "-QAResetAuth", "YES"])
        let signIn = app.buttons["profileSignIn"]
        for _ in 0..<20 where !signIn.isHittable { app.swipeUp() }
        QA.waitFor(signIn, "guest sign-in entry").tap()
        let email = QA.waitFor(app.textFields["Email address"], "email field")
        email.tap(); email.typeText("offline-native-plus@example.test")
        let password = app.secureTextFields["Password"]
        password.tap(); password.typeText("local-offline-native-only")
        let submit = app.buttons["authSubmit"]
        for _ in 0..<4 where !submit.isHittable { app.swipeUp() }
        QA.waitFor(submit, "actual sign-in submission").tap()
        QA.waitFor(app.buttons["openOfflinePacks"], "signed-in profile", timeout: 30)
        app.terminate()
        app = QA.launch(tab: "profile", extraArguments: ["-QAOfflineData", "NO", "-QAUseFirestoreEmulator", "YES"])
        let packs = app.buttons["openOfflinePacks"]
        for _ in 0..<15 where !packs.isHittable { app.swipeUp() }
        QA.waitFor(packs, "storage entry").tap()
        QA.waitFor(app.buttons["chooseOfflinePack"], "choose pack").tap()
        let search = QA.waitFor(app.textFields["offlineParkSearch"], "park selection search")
        search.tap(); search.typeText("Los Gatos Creek")
        // Dismiss the keyboard without navigating away from the selection.
        app.staticTexts["Ready before you leave"].tap()
        let county = app.buttons["offline-choice:county-boundaries_20"]
        for _ in 0..<12 where !county.isHittable { app.swipeUp() }
        QA.waitFor(county, "real County selection", timeout: 60).tap()
        let prepare = app.buttons["prepareOfflinePack"]
        for _ in 0..<8 where !prepare.isHittable { app.swipeDown() }
        QA.waitFor(prepare, "prepare size preview").tap()
        QA.waitFor(app.staticTexts["offlineDownloadSize"], "size before download", timeout: 60)
        XCTAssertFalse(app.staticTexts["Pack downloaded"].exists)
        try QA.audit(app, screen: "Offline pack size preview")
        let previewShot = XCTAttachment(screenshot: app.screenshot()); previewShot.name = "Offline pack size preview"; previewShot.lifetime = .keepAlways; add(previewShot)
        QA.waitFor(app.buttons["downloadOfflinePack"], "confirmed download").tap()
        QA.waitFor(app.staticTexts["Pack downloaded"], "verified pack installed", timeout: 120)
        app.terminate()
        // This DEBUG seam disables online actions; it is not airplane-mode or
        // physical GPS evidence. The UI must reload the persisted snapshot.
        app = QA.launch(tab: "profile", extraArguments: ["-QAOfflineData", "NO", "-QAUseFirestoreEmulator", "YES", "-QAForceOffline", "YES"])
        let stored = app.buttons["openOfflinePacks"]
        for _ in 0..<15 where !stored.isHittable { app.swipeUp() }
        QA.waitFor(stored, "offline storage entry").tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'offline-pack:'")).firstMatch
        QA.waitFor(row, "persisted pack after relaunch").tap()
        QA.waitFor(app.buttons["park-guide:county-boundaries_20"], "stored guide").tap()
        QA.waitFor(app.staticTexts["parkStatus"], "stored source status")
        XCTAssertFalse(app.buttons["Download for offline use"].exists)
        let event = app.buttons["park-event:offline-native-park-event"]
        for _ in 0..<12 where !event.isHittable { app.swipeUp() }
        QA.waitFor(event, "stored event details").tap()
        QA.waitFor(app.staticTexts["RSVP and check-in are available when you're back online."], "offline event action explanation")
        XCTAssertFalse(app.buttons["Open event actions"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let map = app.buttons["parkTrailMap"]
        for _ in 0..<12 where !map.isHittable { app.swipeUp() }
        QA.waitFor(map, "stored trail overlay").tap()
        QA.waitFor(app.descendants(matching: .any).matching(identifier: "parkTrailNotice").firstMatch, "stored trail notice")
        XCTAssertFalse(app.buttons["Directions"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Stored trail view offline preflight"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<3 { app.navigationBars.buttons.firstMatch.tap() }
        QA.waitFor(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'offline-pack:'")).firstMatch, "pack storage after browsing")
        try QA.audit(app, screen: "Offline pack storage")
        QA.waitFor(app.buttons["Delete Los Gatos Creek"], "delete stored pack").tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'offline-pack:'")).firstMatch.exists)
    }

    func testParkTrailMapShowsOfficialNoticeWithoutRouteGuidance() throws {
        let app = QA.launch(tab: "explore", extraArguments: ["-QAOfflineData", "NO", "-QAUseFirestoreEmulator", "YES"])
        let directory = app.buttons["parkDirectory"]
        for _ in 0..<4 where !directory.isHittable { app.swipeUp() }
        QA.waitFor(directory, "park directory").tap()
        let search = QA.waitFor(app.searchFields.firstMatch, "park search")
        search.tap(); search.typeText("Los Gatos Creek")
        app.keyboards.buttons["Search"].tap()
        // City trail reaches sort before the County park. Lazy rows are only
        // exposed to accessibility after scrolling them into the viewport.
        QA.waitFor(app.buttons["park-guide:city-parks_342"], "loaded Los Gatos Creek results", timeout: 60)
        let county = app.buttons["park-guide:county-boundaries_20"]
        for _ in 0..<20 where !county.isHittable { app.swipeUp() }
        QA.waitFor(county, "real County park").tap()
        QA.waitFor(app.staticTexts["parkStatus"], "loaded County guide", timeout: 30)
        let map = app.buttons["parkTrailMap"]
        for _ in 0..<12 where !map.isHittable { app.swipeUp() }
        QA.waitFor(map, "published trail map").tap()
        QA.waitFor(app.descendants(matching: .any).matching(identifier: "parkTrailNotice").firstMatch, "trail safety notice")
        XCTAssertTrue(app.links["Official closures and park information"].exists || app.buttons["Official closures and park information"].exists)
        XCTAssertFalse(app.buttons["Directions"].exists)
        XCTAssertFalse(app.buttons["Start route"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Published trail overlays"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSourceBackedParkGuideRespectsClosedStatusAndAttribution() throws {
        let app = QA.launch(tab: "explore", extraArguments: ["-QAOfflineData", "NO", "-QAUseFirestoreEmulator", "YES"])
        let directory = app.buttons["parkDirectory"]
        for _ in 0..<4 where !directory.isHittable { app.swipeUp() }
        QA.waitFor(directory, "park directory").tap()
        let search = QA.waitFor(app.searchFields.firstMatch, "park search")
        search.tap(); search.typeText("River Glen Elementary Playground")
        app.keyboards.buttons["Search"].tap()
        let row = QA.waitFor(app.buttons["park-guide:city-parks_33"], "real closed City park", timeout: 60)
        row.tap()
        let status = QA.waitFor(app.staticTexts["parkStatus"], "source park status", timeout: 30)
        XCTAssertEqual(status.label, "Closed")
        XCTAssertTrue(app.staticTexts["This site is not listed as open. Published amenities describe the site and do not confirm access."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Closed park guide"; attachment.lifetime = .keepAlways
        add(attachment)
        let attribution = app.staticTexts.matching(identifier: "parkAttribution").firstMatch
        for _ in 0..<10 where !attribution.isHittable { app.swipeUp() }
        XCTAssertTrue(attribution.exists)
        XCTAssertTrue(attribution.label.contains("City of San José"))
        XCTAssertTrue(attribution.label.contains("CC BY"))
        XCTAssertFalse(app.buttons["Directions"].exists)
    }

    private func signupAtNeutralAgeScreen() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "NO", "-QADisableMotion", "YES", "-QAOfflineData", "YES"]
        app.launch()
        for _ in 0..<4 { QA.waitFor(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continue'")).firstMatch, "onboarding continue").tap() }
        QA.waitFor(app.buttons["Sign Up"], "signup mode").tap()
        app.swipeUp()
        QA.waitFor(app.textFields["Birth year"], "neutral birth year")
        XCTAssertFalse(app.textFields["Your name"].exists)
        XCTAssertFalse(app.textFields["Email address"].exists)
        XCTAssertFalse(app.secureTextFields["Password"].exists)
        return app
    }

    func testUnder13NeutralAnswerEndsSignupWithoutAccountFields() {
        let app = signupAtNeutralAgeScreen()
        app.textFields["Birth year"].tap()
        app.textFields["Birth year"].typeText(String(Calendar.current.component(.year, from: Date()) - 12))
        app.buttons["signupAgeContinue"].tap()
        QA.waitFor(app.staticTexts["signupEnded"], "signup ended")
        XCTAssertFalse(app.textFields["Birth year"].exists)
        XCTAssertFalse(app.textFields["Your name"].exists)
        XCTAssertFalse(app.textFields["Email address"].exists)
        XCTAssertFalse(app.buttons["Create Account"].exists)
        XCTAssertFalse(app.buttons["Continue as guest"].exists)
    }

    func testEligibleMinorReachesAccountFieldsOnlyAfterAgeScreen() {
        let app = signupAtNeutralAgeScreen()
        app.textFields["Birth year"].tap()
        app.textFields["Birth year"].typeText(String(Calendar.current.component(.year, from: Date()) - 13))
        app.buttons["signupAgeContinue"].tap()
        QA.waitFor(app.textFields["Your name"], "eligible account fields")
        XCTAssertTrue(app.textFields["Email address"].exists)
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        XCTAssertFalse(app.textFields["Birth year"].exists)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Tabs

    func testAllTabsRender() {
        let anchors: [(tab: String, text: String)] = [
            // The five primary tabs, followed by the rehomed browse surfaces.
            ("events", "Events"), ("plan", "Make a plan."),
            ("friends", "Together, nearby."), ("rewards", "AVAILABLE POINTS"),
            ("profile", "YOUR PROFILE"), ("explore", "Explore"),
            ("map", "Map"), ("collect", "Places collected"),
            ("community", "Community"),
        ]
        for (tab, anchor) in anchors {
            let app = QA.launch(tab: tab)
            QA.waitFor(app.staticTexts[anchor].firstMatch, "\(tab) tab anchor")
            app.terminate()
        }
    }

    func testFiveTabNavigationAndDateChoice() {
        let app = QA.launch(tab: "events")
        QA.waitFor(app.buttons["Plan"].firstMatch, "Plan tab").tap()
        QA.waitFor(app.staticTexts["Make a plan."], "Plan screen")
        QA.waitFor(app.buttons["Pick a date"], "date choice").tap()
        QA.waitFor(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Choose a day")).firstMatch,
            "calendar date picker")

        QA.waitFor(app.buttons["Friends"].firstMatch, "Friends tab").tap()
        QA.waitFor(app.staticTexts["Together, nearby."], "Friends screen")
        QA.waitFor(app.buttons["Rewards"].firstMatch, "Rewards tab").tap()
        QA.waitFor(app.staticTexts["AVAILABLE POINTS"], "Rewards screen")
        QA.waitFor(app.buttons["Profile"].firstMatch, "Profile tab").tap()
        QA.waitFor(app.staticTexts["YOUR PROFILE"], "Profile screen")
    }

    func testPlanRendersVerifiedOfflineFixtureAsCard() {
        let app = QA.launch(tab: "plan")
        QA.waitFor(app.buttons["Find real events"], "plan action").tap()
        QA.waitFor(app.staticTexts["QA Weekend Garden Walk"], "verified sample plan stop")
        app.swipeUp()
        let details = QA.waitFor(app.buttons["Details"].firstMatch, "event details action")
        XCTAssertTrue(details.isHittable, "the plan stop must clear the floating tab bar after scrolling")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "plan-populated-QA-fixture"
        shot.lifetime = .keepAlways
        add(shot)
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
        let app = QA.launch(tab: "rewards")
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
        for _ in 0..<8 where tile.frame.midY > app.frame.height - 160 { app.swipeUp() }
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
            "-QAOfflineData", "YES", // local isolated fixture, never the live project
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
        app.launchArguments += ["-hasCompletedOnboarding", "NO", "-QADisableMotion", "YES", "-QAOfflineData", "YES"]
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
