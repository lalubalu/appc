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
        QA.waitFor(app.staticTexts[anchor], "\(tab) anchor '\(anchor)'")
        try QA.audit(app, screen: tab)
    }

    func testAuditEventsTab() throws     { try auditTab("events", anchor: "Events") }
    func testAuditExploreTab() throws    { try auditTab("explore", anchor: "Explore") }
    func testAuditCollectTab() throws    { try auditTab("collect", anchor: "Collect") }
    func testAuditCommunityTab() throws  { try auditTab("community", anchor: "Community") }
    func testAuditProfileTab() throws    { try auditTab("profile", anchor: "PLAYER CARD") }

    func testAuditRewardsStore() throws {
        let app = QA.launch(tab: "profile")
        QA.waitFor(app.buttons["Rewards"].firstMatch, "rewards button").tap()
        QA.waitFor(app.staticTexts["AVAILABLE POINTS"], "rewards store")
        try QA.audit(app, screen: "rewards-store")
    }

    func testAuditPaywall() throws {
        let app = QA.launch(tab: "profile")
        QA.waitFor(app.staticTexts["Verdure+"].firstMatch, "Verdure+ settings row").tap()
        QA.waitFor(app.buttons["Start Verdure Plus"], "paywall CTA")
        try QA.audit(app, screen: "paywall")
    }

    func testAuditOnboardingFirstPage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "NO", "-QADisableMotion", "YES"]
        app.launch()
        QA.waitFor(app.staticTexts["Step Outside.\nConnect Within."], "onboarding hero title")
        try QA.audit(app, screen: "onboarding-1")
    }
}
