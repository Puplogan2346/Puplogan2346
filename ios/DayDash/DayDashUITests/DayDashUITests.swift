import XCTest

/// First automated coverage for the DayDash iOS app.
///
/// These are deliberately lightweight *smoke* tests: launch the real app and
/// prove that each of the five tabs loads and renders without crashing,
/// attaching a screenshot of every screen so a human (or CI artifact) can eye
/// the result. They intentionally avoid asserting on copy or layout that is
/// expected to change — the contract here is "the app boots and every tab is
/// reachable," which is exactly the surface that had never been verified.
final class DayDashUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launch, then tap through every tab, screenshotting each.
    @MainActor
    func testVisitsEveryTab() throws {
        let app = XCUIApplication()
        // Suppress the first-run welcome sheet so the tab bar is immediately reachable.
        app.launchArguments += ["-skipOnboarding"]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "App should reach the foreground after launch"
        )

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 15),
            "The main tab bar should appear on launch"
        )

        // Today is selected on launch — capture it before navigating.
        attach(app.screenshot(), named: "01-Today-launch")

        // Visit the rest, then return to Today.
        let order = ["Tasks", "Habits", "Brain Dump", "Assistant", "Today"]
        for (i, name) in order.enumerated() {
            let button = tabBar.buttons[name]
            XCTAssertTrue(
                button.waitForExistence(timeout: 5),
                "Tab '\(name)' should exist in the tab bar"
            )
            button.tap()
            XCTAssertTrue(
                button.exists,
                "Tab '\(name)' should still be present after tapping it"
            )
            attach(app.screenshot(), named: String(format: "%02d-%@", i + 2, name))
        }
    }

    /// A cheap structural assertion: all five expected tabs exist.
    @MainActor
    func testTabBarHasAllFiveTabs() throws {
        let app = XCUIApplication()
        // Suppress the first-run welcome sheet so the tab bar is immediately reachable.
        app.launchArguments += ["-skipOnboarding"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "Tab bar should exist")

        for name in ["Today", "Tasks", "Habits", "Brain Dump", "Assistant"] {
            XCTAssertTrue(
                tabBar.buttons[name].exists,
                "Expected a '\(name)' tab in the tab bar"
            )
        }
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
