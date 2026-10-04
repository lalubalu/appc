import XCTest

@MainActor final class LivePartnerConsentUITests: XCTestCase {
    func testNearbyDealsRequireSeparatePromotionalConsent() {
        continueAfterFailure = false
        let app = QA.launch(tab: "profile", extraArguments: ["-QAOfflineData", "NO", "-QAUseFirestoreEmulator", "YES", "-QAResetAuth", "YES"])
        let signIn = app.buttons["profileSignIn"]
        for _ in 0..<20 where !signIn.isHittable { app.swipeUp() }
        QA.waitFor(signIn, "Sign in").tap()
        let email = QA.waitFor(app.textFields["Email address"], "Email")
        email.tap(); email.typeText("qa-stories-native-owner@example.test")
        let password = app.secureTextFields["Password"]
        password.tap(); password.typeText("local-story-native-only")
        let submit = app.buttons["authSubmit"]
        for _ in 0..<4 where !submit.isHittable { app.swipeUp() }
        QA.waitFor(submit, "Sign-in submit").tap()
        QA.waitFor(app.buttons["openOfflinePacks"], "Signed-in profile", timeout: 30)
        let notifications = app.buttons["Notifications"]
        for _ in 0..<25 where !notifications.isHittable { app.swipeUp() }
        QA.waitFor(notifications, "Notifications settings").tap()
        let toggle = app.switches["livePartnerAlertsToggle"]
        for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
        QA.waitFor(toggle, "Adult-only nearby deals", timeout: 20)
        XCTAssertEqual(toggle.value as? String, "0", "Off by default")
        // The labelled SwiftUI wrapper includes the text; tap its actual
        // native switch, rather than depending on label hit-test propagation.
        let nativeSwitch = toggle.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() } else { toggle.tap() }
        QA.waitFor(app.buttons["confirmLivePartnerConsent"], "Separate promotional consent")
        XCTAssertFalse(app.alerts.firstMatch.exists, "The toggle alone must not request Always location")
        let consent = XCTAttachment(screenshot: app.screenshot()); consent.name = "live-partner-promotional-consent"; consent.lifetime = .keepAlways; add(consent)
        app.buttons["Not now"].tap()
        XCTAssertEqual(toggle.value as? String, "0", "Cancelling never enables monitoring")
    }
}
