import XCTest

@MainActor final class PartnerSurfaceTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSeparateMapLayerControlCanBeToggled() throws {
        let app = QA.launch(tab: "map")
        let toggle = QA.waitFor(app.descendants(matching: .any).matching(identifier: "partnerMapLayer").firstMatch,
                                "partner layer toggle")
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        XCTAssertTrue(toggle.exists)
        toggle.tap()
        try QA.audit(app, screen: "partner-map-layer")
    }

    func testRewardsOffersNearbyAndDefaultSort() {
        let app = QA.launch(tab: "rewards")
        QA.waitFor(app.staticTexts["AVAILABLE POINTS"], "Rewards")
        let nearby = QA.waitFor(app.buttons["Nearby"], "Nearby rewards sort")
        nearby.tap()
        XCTAssertTrue(app.staticTexts["Location unavailable · using the default order"].waitForExistence(timeout: 5))
        QA.waitFor(app.buttons["Default"], "default rewards order").tap()
    }
}
