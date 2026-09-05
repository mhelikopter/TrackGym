import XCTest

final class TrackGymUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_appLaunchesAndShowsRootView() throws {
        let app = XCUIApplication()
        app.launch()

        // The root ContentView renders a TabView with three tabs.
        XCTAssertTrue(app.tabBars.firstMatch.exists, "Tab bar should be visible after app launch")
    }
}
