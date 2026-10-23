import XCTest

/// The judge's path through the app against the local emulators with real ingested
/// events: fresh install → onboarding → sign-in → every tab → feed with reasons →
/// event detail → places → place detail → map → settings → Terms/Privacy.
/// Fails if a main screen is blank, shows an error, or hasn't settled within 15 s.
/// Screenshots are attached in order (`NN-name`) so the demo set can be exported.
@MainActor
final class DemoWalkthroughUITests: XCTestCase {
    private var shot = 0
    private let loadTimeout: TimeInterval = 15

    override func setUp() { continueAfterFailure = false }

    // MARK: Helpers

    private func launch() -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: QA.sanJose)
        let app = XCUIApplication()
        app.launchArguments += [
            "-QAFreshInstall", "YES",
            "-QAUseFirestoreEmulator", "YES", "-QAEmulatorHost", "127.0.0.1",
            "-QAOfflineData", "NO", "-QAResetAuth", "YES", "-QADisableMotion", "YES",
            "-dailyGem.splashDay", QA.today,
        ]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        shot += 1
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = String(format: "%02d-%@", shot, name); a.lifetime = .keepAlways
        add(a)
    }

    /// System prompts (location, notifications, "Save Password?") sit above the app.
    private func clearSystemAlerts(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The keychain "Save Password?" sheet is a remote view: a synthesized tap on its
        // "Not Now" does not reach it. Backgrounding the app dismisses it as Not Now.
        // Its text is not reliably in the app's tree, so after sign-in always background once.
        _ = app.staticTexts["Save Password?"].waitForExistence(timeout: 10)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { return }
            for label in ["Allow While Using App", "Allow Once", "Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); break
            }
        }
    }

    private static let errorPredicate = NSPredicate(format:
        "label CONTAINS[c] 'couldn’t' OR label CONTAINS[c] 'couldn\\'t' OR label CONTAINS[c] 'something went wrong' " +
        "OR label BEGINSWITH[c] 'error' OR label CONTAINS[c] 'an error occurred' OR label CONTAINS[c] 'isn\\'t configured' " +
        "OR label CONTAINS[c] 'lorem'")

    /// A screen counts as loaded when `anchor` is present, no spinner remains,
    /// it carries real text, and no error copy is on screen — all within 15 s.
    private func assertLoaded(_ app: XCUIApplication, _ screen: String, anchor: XCUIElement,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(anchor.waitForExistence(timeout: loadTimeout), "\(screen): never appeared", file: file, line: line)
        let settled = NSPredicate { _, _ in app.activityIndicators.count == 0 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: settled, evaluatedWith: nil)], timeout: loadTimeout), .completed,
                       "\(screen): still loading after \(Int(loadTimeout)) s", file: file, line: line)
        XCTAssertGreaterThanOrEqual(app.staticTexts.count, 3, "\(screen): blank", file: file, line: line)
        let errors = app.staticTexts.matching(Self.errorPredicate)
        XCTAssertEqual(errors.count, 0, "\(screen): error on screen — \(errors.firstMatch.exists ? errors.firstMatch.label : "")",
                       file: file, line: line)
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: loadTimeout), "tab \(name) missing")
        button.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) {
        var swiped = false
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) { app.swipeUp(); swiped = true }
        // Let the scroll coast to a stop: a tap during deceleration only stops the scroll.
        if swiped { QA.settle(element) }
    }

    private func type(_ text: String, into field: XCUIElement) { QA.type(text, into: field) }

    private func continueTap(_ app: XCUIApplication) {
        let cta = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continue'")).firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 8)); cta.tap()
    }

    /// Fresh install → onboarding → sign-in on the Auth emulator → main tabs.
    private func onboardAndSignIn(_ app: XCUIApplication, email account: String = "demo-judge@example.test",
                                  password: String = "local-demo-walkthrough", picks: [String] = ["Parks", "Community"]) {
        assertLoaded(app, "Onboarding", anchor: app.staticTexts["Step Outside.\nConnect Within."])
        snap(app, "onboarding")
        let first = app.buttons["\(picks[0]) interest"].firstMatch
        QA.continueUntil(first, in: app)
        for pick in picks { app.buttons["\(pick) interest"].firstMatch.tap() }
        snap(app, "onboarding-interests")
        continueTap(app)

        // Sign in to the local demo account (functions/scripts/demo-account-local.mjs).
        // Sign-up is not driven here: the simulator's Strong Password sheet takes over
        // the new-password field, so typed passwords never land.
        let email = app.textFields["Email address"]
        XCTAssertTrue(email.waitForExistence(timeout: 8), "auth screen missing")
        snap(app, "sign-in")
        type(account, into: email)
        // Return closes the software keyboard, which otherwise covers the submit button.
        type(password + "\n", into: app.secureTextFields["Password"])
        let submit = app.buttons["authSubmit"]
        scrollTo(submit, in: app, maxSwipes: 4)
        submit.tap()
        XCTAssertTrue(app.buttons["Discover"].firstMatch.waitForExistence(timeout: 30),
                      "sign-in did not reach the main tabs (seed the account with scripts/demo-account-local.mjs)")
        clearSystemAlerts(app)
    }

    // MARK: The walkthrough

    func testJudgeWalkthrough() {
        let app = launch()
        onboardAndSignIn(app)

        // Events feed with real events and the ranked reasons line.
        let poster = app.buttons.matching(identifier: "event-poster").firstMatch
        assertLoaded(app, "Events feed", anchor: poster)
        snap(app, "events-feed")
        let ranked = app.buttons.matching(NSPredicate(format: "label CONTAINS ', Why: '")).firstMatch
        scrollTo(ranked, in: app, maxSwipes: 8)
        XCTAssertTrue(ranked.waitForExistence(timeout: loadTimeout), "no card carries a reasons line")
        snap(app, "events-feed-reasons")

        // Event detail: why, show less, hide, series.
        // The feed re-renders as the ranked slate lands; a tap mid-update can be dropped.
        // One retry, recorded in the log, so a genuinely dead card still fails below.
        ranked.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        if !app.buttons["hideEvent"].firstMatch.waitForExistence(timeout: 6) {
            XCTContext.runActivity(named: "RETRY: event card tap did not open detail") { _ in }
            ranked.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        }
        let why = app.descendants(matching: .any).matching(identifier: "whySeeingThis").firstMatch
        assertLoaded(app, "Event detail", anchor: app.buttons["hideEvent"].firstMatch)
        snap(app, "event-detail")
        scrollTo(why, in: app, maxSwipes: 6)
        XCTAssertTrue(why.exists, "Why you're seeing this missing")
        snap(app, "event-detail-why")
        let less = app.buttons["feedbackLess"]
        scrollTo(less, in: app, maxSwipes: 4)
        XCTAssertTrue(less.exists, "Show less missing")
        if app.buttons["seriesMoreDates"].exists { snap(app, "event-detail-series") }
        less.tap()
        snap(app, "event-detail-feedback")
        app.buttons["hideEvent"].tap()
        XCTAssertTrue(poster.waitForExistence(timeout: loadTimeout), "feed did not return after Hide")

        // Places, then a place detail. When an OpenStreetMap place is listed (ids `osm-`,
        // encoded in the card identifier), open it and require its licence credit.
        app.buttons["Places"].firstMatch.tap()
        let anyPlace = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'nearbyPlaceCard'")).firstMatch
        scrollTo(anyPlace, in: app, maxSwipes: 6)
        assertLoaded(app, "Places", anchor: anyPlace)
        snap(app, "places")
        let osmPlace = app.buttons["nearbyPlaceCard-osm"].firstMatch
        let isOSM = osmPlace.exists
        (isOSM ? osmPlace : anyPlace).tap()
        assertLoaded(app, "Place detail", anchor: app.navigationBars.firstMatch)
        snap(app, "place-detail")
        if isOSM {
            let osm = app.links["© OpenStreetMap contributors"].firstMatch
            scrollTo(osm, in: app, maxSwipes: 8)
            XCTAssertTrue(osm.exists, "OpenStreetMap credit missing on an OSM place")
            snap(app, "credit-osm-place")
        } else {
            XCTContext.runActivity(named: "NOTE: no OpenStreetMap place nearby (Overpass unavailable); OSM credit covered by DataCreditTests") { _ in }
        }
        app.navigationBars.buttons.firstMatch.tap()

        // Map.
        app.buttons["Map"].firstMatch.tap()
        assertLoaded(app, "Map", anchor: app.maps.firstMatch)
        snap(app, "map")

        // The other four tabs.
        for (name, label) in [("Plan", "plan"), ("Friends", "friends"), ("Rewards", "rewards"), ("Profile", "profile")] {
            tab(app, name)
            assertLoaded(app, name, anchor: app.buttons[name].firstMatch)
            snap(app, label)
        }

        // Settings → Terms (to the end) → Privacy.
        let legal = app.buttons["Terms & Privacy"].firstMatch
        scrollTo(legal, in: app)
        snap(app, "settings")
        legal.tap()
        let acknowledgements = app.staticTexts["Data and acknowledgements"]
        assertLoaded(app, "Terms", anchor: app.navigationBars["Legal"])
        snap(app, "terms")
        scrollTo(acknowledgements, in: app, maxSwipes: 30)
        XCTAssertTrue(acknowledgements.exists, "Data and acknowledgements missing from Terms")
        for _ in 0..<4 { app.swipeUp() }
        snap(app, "credit-terms-end")
        app.buttons["Privacy Policy"].firstMatch.tap()
        assertLoaded(app, "Privacy", anchor: app.navigationBars["Legal"])
        snap(app, "privacy")
    }

    /// For You follows each account's own picks (accounts from
    /// `scripts/foryou-interests-e2e.mjs --keep`): the ranked cards say which pick they match.
    func testForYouFollowsEachAccountsPicks() {
        for (account, picks, name) in [("foryou-student-trails@example.test", ["Parks", "Trails"], "foryou-student-trails"),
                                       ("foryou-community-sports@example.test", ["Community", "Sports"], "foryou-community")] {
            let app = launch()
            onboardAndSignIn(app, email: account, password: "local-foryou-check", picks: picks)
            let pick = picks.map { "label CONTAINS 'Because you like \($0)'" }.joined(separator: " OR ")
            let ranked = app.buttons.matching(NSPredicate(format: pick)).firstMatch
            XCTAssertTrue(ranked.waitForExistence(timeout: 30), "\(name): no For You card names one of \(picks)")
            QA.reveal(ranked, in: app, maxSwipes: 4)
            snap(app, name)
            app.terminate()
        }
    }

    /// Planner with real nearby places and live weather. Needs the planner's model key on
    /// the local Functions emulator; without it the server answers "isn't configured yet".
    func testAdventurePlannerShowsPlanWithWeatherCredit() throws {
        let app = launch()
        onboardAndSignIn(app)
        app.buttons["Places"].firstMatch.tap()
        let open = app.buttons["Plan my adventure"].firstMatch
        QA.reveal(open, in: app, maxSwipes: 6)
        if !open.waitForExistence(timeout: loadTimeout) {
            // ExploreView offers the planner only with two or more places that have coordinates.
            throw XCTSkip("Planner entry hidden: fewer than two nearby places (OpenStreetMap/Overpass unreachable).")
        }
        open.tap()
        // The sheet's CTA shares the tile's label; take the one on top (the sheet).
        XCTAssertTrue(app.staticTexts["How long have you got?"].waitForExistence(timeout: loadTimeout), "planner sheet missing")
        let runs = app.buttons.matching(NSPredicate(format: "label == 'Plan my adventure'"))
        let run = runs.element(boundBy: max(0, runs.count - 1))
        snap(app, "planner")
        QA.reveal(run, in: app, maxSwipes: 4)
        run.tap()
        let credit = app.links["Weather data by Open-Meteo.com"]
        // AdventurePlannerService maps the server's failed-precondition to its own copy.
        let notConfigured = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] \"isn't configured\" OR label CONTAINS[c] \"isn't switched on\"")).firstMatch
        let done = NSPredicate { _, _ in credit.exists || notConfigured.exists }
        _ = XCTWaiter.wait(for: [expectation(for: done, evaluatedWith: nil)], timeout: 60)
        snap(app, "planner-result")
        if notConfigured.exists {
            throw XCTSkip("Local Functions emulator has no ANTHROPIC_API_KEY (functions/.secret.local); the planner cannot run here.")
        }
        assertLoaded(app, "Planner plan", anchor: credit)
        scrollTo(credit, in: app, maxSwipes: 3)
        snap(app, "credit-weather-planner")
    }
}
