import XCTest

// MARK: - Automated accessibility audits (Apple's audit engine, iOS 17+)
//
// One audit per primary screen. Missing labels / bad hit regions / trait
// problems FAIL; contrast + dynamic-type + clipping findings are recorded as
// activity notes and tracked as design-system items in QA.md.

@MainActor
final class AccessibilityAuditTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func auditTab(_ tab: String, anchor: String) throws {
        let app = QA.launch(tab: tab)
        // Terminate at the end of each test so the next audit can't attach to a
        // stale process (a source of "Invalid target app" on CI).
        addTeardownBlock { app.terminate() }
        QA.waitFor(app.staticTexts[anchor], "\(tab) anchor '\(anchor)'")
        try QA.audit(app, screen: tab)
    }

    func testAuditEventsTab() throws     { try auditTab("events", anchor: "Events") }
    func testAuditExploreTab() throws    { try auditTab("explore", anchor: "Explore") }
    func testAuditCollectTab() throws    { try auditTab("collect", anchor: "Places collected") }
    func testAuditCommunityTab() throws  { try auditTab("community", anchor: "Community") }
    func testAuditProfileTab() throws    { try auditTab("profile", anchor: "YOUR PROFILE") }
    func testAuditPlanTab() throws       { try auditTab("plan", anchor: "Make a plan.") }
    func testAuditFriendsTab() throws    { try auditTab("friends", anchor: "Together, nearby.") }

    func testAuditRewardsStore() throws {
        let app = QA.launch(tab: "rewards")
        QA.waitFor(app.staticTexts["AVAILABLE POINTS"], "rewards store")
        try QA.audit(app, screen: "rewards-store")
    }

    func testAuditPaywall() throws {
        let app = QA.launch(tab: "profile")
        QA.waitFor(app.staticTexts["Verdure+"].firstMatch, "Verdure+ settings row").tap()
        QA.waitFor(app.buttons["Start Verdure Plus"], "paywall CTA")
        try QA.audit(app, screen: "paywall")
    }

    /// The Adventure Planner sheet. Audited WITHOUT generating a plan: the
    /// planner needs a deployed Cloud Function, so a test that tried to produce
    /// an itinerary would either hit the network or quietly assert nothing.
    /// The controls the user meets first — duration chips and the CTA — are on
    /// screen immediately and are what this checks.
    func testAuditAdventurePlanner() throws {
        let app = QA.launch(tab: "explore")
        addTeardownBlock { app.terminate() }
        let entry = QA.waitFor(app.buttons["Plan my adventure"].firstMatch,
                               "adventure planner entry tile")
        entry.tap()
        QA.waitFor(app.staticTexts["How long have you got?"], "planner sheet")
        try QA.audit(app, screen: "adventure-planner")
    }

    // MARK: Surfaces added this sprint
    //
    // H4. Each of these is a screen a user can reach and act on, so each gets
    // the same audit the older screens get rather than a visual once-over.

    func testAuditNotificationSettings() throws {
        let app = QA.launch(tab: "profile")
        addTeardownBlock { app.terminate() }
        QA.waitFor(app.staticTexts["Notifications"].firstMatch, "notifications settings row").tap()
        QA.waitFor(app.staticTexts["What we send"], "notification settings sheet")
        try QA.audit(app, screen: "notification-settings")
    }

    func testAuditMyPerkCodes() throws {
        let app = QA.launch(tab: "rewards")
        addTeardownBlock { app.terminate() }
        QA.waitFor(app.staticTexts["AVAILABLE POINTS"], "rewards store")
        // My Codes is reachable whether or not any code has been claimed — the
        // empty state is itself a surface that has to pass.
        let myCodes = app.buttons["My Codes"].firstMatch
        if myCodes.waitForExistence(timeout: 4) {
            myCodes.tap()
            try QA.audit(app, screen: "my-perk-codes")
        } else {
            XCTFail("My Codes entry point is missing from the rewards store")
        }
    }

    func testAuditOnboardingFirstPage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "NO", "-QADisableMotion", "YES", "-QAOfflineData", "YES"]
        app.launch()
        QA.waitFor(app.staticTexts["Step Outside.\nConnect Within."], "onboarding hero title")
        try QA.audit(app, screen: "onboarding-1")
    }
}
