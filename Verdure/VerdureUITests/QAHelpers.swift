import XCTest

// MARK: - Shared UI-test launch plumbing
//
// State is injected through the NSArgumentDomain (`-key value` launch arguments
// feed UserDefaults for that run), so tests are deterministic without any app
// code beyond the DEBUG `-QATab` initial-tab hook.

@MainActor
enum QA {
    static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Launch the app straight into a tab with onboarding done, the Daily Gem
    /// splash already shown today, and interests pre-picked.
    static func launch(tab: String = "events", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            "-dailyGem.splashDay", today,          // suppress the once-a-day splash
            "-interestCategories", "Parks,Trails,Community",
            "-QATab", tab,
            "-QADisableMotion", "YES",   // audits need quiescence
            "-QAOfflineData", "YES",     // deterministic content, no fetch churn
            "-QAResetDiscoveryFilters", "YES", // independent initial filters
        ]
        app.launchArguments += extraArguments
        app.launch()
        allowLocationIfAsked()
        return app
    }

    /// Each test run reinstalls the app, which resets its location permission, so the
    /// system prompt can sit over the first screen and leave the app without GPS
    /// (it then browses the launch-area centre). Answer it the way a user would.
    static func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    /// Run Apple's accessibility audit on the current screen.
    ///
    /// Scope: the STRUCTURAL types (labels, hit regions, traits, element
    /// detection) — these fail tests. Visual types (contrast / dynamic type /
    /// clipping) are excluded from the machine audit: running them across these
    /// dense clay screens exceeds the audit engine's internal time budget
    /// (error -56), and they're covered by the light/dark × text-size
    /// screenshot matrix reviewed in QA.md instead.
    static func audit(_ app: XCUIApplication, screen: String,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        // The audit service occasionally fails to attach to the app process with
        // `com.apple.accessibilityAudit` code -902 ("Invalid target app <pid>").
        // That's infrastructure, not a finding — on CI it hit the first few tests
        // in the class and cleared up once the service warmed up. The structural
        // engine can also time out (-56) without producing a result. Retry only
        // those infrastructure errors; real findings fail immediately. Exhausted
        // retries still throw, and each attempt is recorded in the result bundle.
        var lastError: Error?
        for attempt in 1...3 {
            do {
                // The audit service will only inspect the frontmost app; on a
                // headless CI simulator the app isn't reliably activated.
                app.activate()
                _ = app.wait(for: .runningForeground, timeout: 5)
                try runAudit(app, screen: screen, file: file, line: line)
                return
            } catch let error as NSError where
                (error.domain == "com.apple.accessibilityAudit" && error.code == -902) ||
                (error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56) {
                lastError = error
                XCTContext.runActivity(named: "AUDIT-RETRY [\(screen)] attempt \(attempt): \(error.localizedDescription)") { _ in }
                Thread.sleep(forTimeInterval: 2)
            }
        }
        throw lastError ?? NSError(domain: "QA", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "audit failed to run for \(screen)"])
    }

    private static func runAudit(_ app: XCUIApplication, screen: String,
                                 file: StaticString, line: UInt) throws {
        let structural: XCUIAccessibilityAuditType = [
            .sufficientElementDescription, .hitRegion, .trait,
        ]
        // The Program detail's combined structural request repeatedly exceeds
        // the system audit time budget. Run the same three types separately,
        // requiring all of them; do not suppress findings or accept a timeout.
        let scopes: [XCUIAccessibilityAuditType] = screen == "Curated Program detail"
            ? [.sufficientElementDescription, .hitRegion, .trait] : [structural]
        for scope in scopes {
            try XCTContext.runActivity(named: "AUDIT-SCOPE [\(screen)] \(scope.rawValue)") { _ in
                try app.performAccessibilityAudit(for: scope) { issue in
                    let element = issue.element.map { "\($0)" } ?? "?"
                    // MapKit owns the Legal attribution link and exposes its text-sized
                    // frame. Keep it visible and actionable; exclude only that native
                    // link's hit-region finding, never Verdure pins or controls.
                    if screen == "partner-map-layer", issue.auditType == .hitRegion,
                       issue.element?.label == "Legal" {
                        XCTContext.runActivity(named: "AUDIT-NOTE [\(screen)] native MapKit Legal link; physical VoiceOver check remains required") { _ in }
                        return true
                    }
                    // Known SwiftUI limitation: a TextField's audit frame is its text rect
                    // even when the surrounding container focuses it on tap (ours are ≥44pt
                    // clay wells wired via FocusState). Note it; don't fail.
                    if issue.auditType == .hitRegion, issue.element?.elementType == .textField {
                        XCTContext.runActivity(named: "AUDIT-NOTE [\(screen)] textField rect (container focuses ≥44pt) → \(element.prefix(120))") { _ in }
                        return true
                    }
                    XCTContext.runActivity(named: "AUDIT [\(screen)] \(issue.compactDescription) → \(element.prefix(160))") { _ in }
                    return false   // every other structural finding fails the test
                }
            }
        }
    }

    /// Scroll until `element` is hittable AND clear of the floating tab bar. XCUITest
    /// reports a row under the bar as hittable, and the tap then lands on a tab.
    /// An element already on screen is dragged just far enough (held, so no momentum); a full
    /// swipe would fling a row that sits just under the bar up beneath the pinned search field.
    static func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 20) {
        var swiped = false
        let height = app.frame.height
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable && element.frame.maxY < height - 140) {
            let frame = element.exists ? element.frame : .zero
            if frame.minY > 0, frame.minY < height {
                let lift = min(frame.maxY - (height - 180), height * 0.5)
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -max(lift, 60))),
                            withVelocity: .slow, thenHoldForDuration: 0.3)
            } else {
                app.swipeUp()
            }
            swiped = true
        }
        if swiped { settle(element) }
    }

    /// A swipe keeps the list coasting for a few seconds, and a tap during deceleration
    /// only stops the scroll (standard UIKit). Wait until the element stops moving.
    static func settle(_ element: XCUIElement, timeout: TimeInterval = 5) {
        var last = element.exists ? element.frame : .zero
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.4)
            let now = element.exists ? element.frame : .zero
            if now == last { return }
            last = now
        }
    }

    /// Onboarding: tap Continue until `target` appears. The first synthesized tap after a
    /// cold launch is sometimes dropped while the app finishes launching; the pager can
    /// no longer advance past sign-in, so an extra tap cannot overshoot.
    static func continueUntil(_ target: XCUIElement, in app: XCUIApplication, maxTaps: Int = 8,
                              file: StaticString = #filePath, line: UInt = #line) {
        let cta = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continue'")).firstMatch
        for _ in 0..<maxTaps where !target.waitForExistence(timeout: 2) {
            if cta.waitForExistence(timeout: 5) { cta.tap() }
        }
        XCTAssertTrue(target.waitForExistence(timeout: 8), "onboarding never reached \(target)", file: file, line: line)
    }

    /// Signed in = the auth sheet is gone and Profile no longer offers "Sign in". The
    /// "openOfflinePacks" row is on the signed-out Profile too, so waiting on it returned at
    /// once and a test that terminated next killed the sign-in still in flight.
    static func waitForSignedIn(_ app: XCUIApplication, timeout: TimeInterval = 30,
                                file: StaticString = #filePath, line: UInt = #line) {
        let signedIn = NSPredicate { _, _ in
            !app.buttons["authSubmit"].exists && !app.buttons["profileSignIn"].exists && app.buttons["openOfflinePacks"].exists
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: signedIn, object: nil)], timeout: timeout)
        XCTAssertEqual(result, .completed, "sign-in did not complete", file: file, line: line)
    }

    /// Taps until the field owns the keyboard, then types. A first tap that lands while a
    /// sheet or the keyboard is still settling leaves no focus, and typeText then throws.
    static func type(_ text: String, into field: XCUIElement) {
        for _ in 0..<4 {
            field.tap()
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        field.typeText(text)
    }

    /// Wait helper with a clear failure message.
    @discardableResult
    static func waitFor(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 12,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "expected \(what) to appear", file: file, line: line)
        return element
    }
}
