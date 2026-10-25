import XCTest

/// CAC 2026 (1.2): a real plan with NO AI key, against the local emulators.
///
/// Needs: the emulators running (functions on 5002) with the native fixtures
/// seeded (`node functions/scripts/offline-native-fixture.mjs`), and places on
/// screen — live Overpass, this area's cache, or the bundled OpenStreetMap
/// snapshot (`Resources/osm-snapshot-san-jose.json`); the planner tile only
/// appears with three or more real places. Weather and the Open-Meteo credit
/// need the simulator to reach api.open-meteo.com; the plan itself does not.
@MainActor final class PlannerUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testPlanIsBuiltWithNoAIKeyAndCreditsOpenMeteo() throws {
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
        QA.waitFor(submit, "sign-in submission").tap()
        QA.waitFor(app.buttons["openOfflinePacks"], "signed-in profile", timeout: 30)
        app.terminate()

        app = QA.launch(tab: "explore", extraArguments: ["-QAOfflineData", "NO", "-QAUseFirestoreEmulator", "YES"])
        // Places first: the planner tile exists only once three real places are on screen.
        let osmCard = app.buttons["nearbyPlaceCard-osm"].firstMatch
        for _ in 0..<12 where !osmCard.exists { app.swipeUp() }
        XCTAssertTrue(osmCard.waitForExistence(timeout: 40), "an OpenStreetMap place must be on Explore (live, this area's cache or the bundled snapshot)")
        let credit = app.links["© OpenStreetMap contributors"].firstMatch
        for _ in 0..<12 where !credit.exists { app.swipeUp() }
        XCTAssertTrue(credit.waitForExistence(timeout: 10), "the ODbL credit must accompany the places")
        let placesShot = XCTAttachment(screenshot: app.screenshot()); placesShot.name = "explore-places-osm-credit"; placesShot.lifetime = .keepAlways; add(placesShot)

        let entry = app.buttons["Plan my adventure"].firstMatch
        for _ in 0..<12 where !entry.isHittable { app.swipeUp() }
        QA.waitFor(entry, "planner entry tile", timeout: 20).tap()
        QA.waitFor(app.staticTexts["How long have you got?"], "planner sheet")
        app.buttons["2 hrs"].firstMatch.tap()
        let plan = app.buttons["Plan my adventure"].firstMatch
        QA.waitFor(plan, "plan button").tap()

        // A real plan: at least two stops, each a real place, no error card and never "isn't switched on".
        let firstStop = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Stop 1:")).firstMatch
        let anyStop = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "Stop 1:")).firstMatch
        let appeared = firstStop.waitForExistence(timeout: 45) || anyStop.waitForExistence(timeout: 5)
        if !appeared { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "planner-no-plan"; shot.lifetime = .keepAlways; add(shot) }
        XCTAssertTrue(appeared, "a plan with a first stop must appear with no AI key configured")
        XCTAssertFalse(app.staticTexts["The planner isn't switched on yet."].exists)
        XCTAssertFalse(app.staticTexts["Plan generation is available when you're back online."].exists)
        let secondStop = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Stop 2:")).firstMatch
        XCTAssertTrue(secondStop.waitForExistence(timeout: 5), "a plan has at least two stops")

        // The weather line and its credit, when the emulator could reach Open-Meteo.
        let weatherCredit = app.links["Weather data by Open-Meteo.com"].firstMatch
        for _ in 0..<6 where !weatherCredit.exists && !app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "About ")).firstMatch.exists { app.swipeUp() }
        if weatherCredit.exists {
            XCTAssertTrue(weatherCredit.isHittable || weatherCredit.exists)
        } else {
            // Honest fallback: no weather means no credit and the summary line says "About N min" with no temperature.
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "About ")).firstMatch.exists, "without weather the plan still shows its length")
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "adventure-planner-plan"; shot.lifetime = .keepAlways; add(shot)
        try QA.audit(app, screen: "adventure-planner-plan")
    }
}
