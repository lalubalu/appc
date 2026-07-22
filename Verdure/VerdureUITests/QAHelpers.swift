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
        ]
        app.launchArguments += extraArguments
        app.launch()
        return app
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
        let structural: XCUIAccessibilityAuditType = [
            .sufficientElementDescription, .hitRegion, .trait,
        ]
        try app.performAccessibilityAudit(for: structural) { issue in
            let element = issue.element.map { "\($0)" } ?? "?"
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

    /// Wait helper with a clear failure message.
    @discardableResult
    static func waitFor(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 12,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "expected \(what) to appear", file: file, line: line)
        return element
    }
}
