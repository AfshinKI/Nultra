import XCTest

final class NultraUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["demo.banner"].waitForExistence(timeout: 15))
        return app
    }
    func testTwoColumnGridAndDisconnectedPowerRename() throws {
        let app = launchDemo()
        let first = app.buttons["device.BEDROOM1"]
        let second = app.buttons["device.CORNER01"]
        XCTAssertTrue(first.isHittable); XCTAssertTrue(second.isHittable)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(second.frame.minX, first.frame.minX)
        XCTAssertTrue(app.buttons["toggle.SHELFLED"].isHittable, "All six sample switches fit on the mini")
        screenshot("01-dashboard-13-mini")
        app.buttons["toggle.DESKLAMP"].tap()
        XCTAssertTrue(app.buttons["toggle.DESKLAMP"].label.contains("Off"))
        app.buttons["device.DESKLAMP"].tap()
        XCTAssertTrue(app.staticTexts["connection.status"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["connection.status"].label, "Disconnected")
        app.buttons["power.on"].tap()
        XCTAssertEqual(app.staticTexts["power.state"].label, "Power is on")
        XCTAssertEqual(app.staticTexts["connection.status"].label, "Disconnected")
        screenshot("02-switch-controls")
        app.buttons["Rename"].tap()
        XCTAssertEqual(app.staticTexts["connection.status"].label, "Disconnected", "Editing must not connect")
        let field = app.textFields["rename.field"]
        if !field.isHittable { app.swipeUp() }
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "OFFICE01")
        let save = app.buttons["rename.save"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["OFFICE01"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["connection.status"].label, "Disconnected")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["device.OFFICE01"].exists)
        app.buttons["settings"].tap()
        let toggle = app.switches["demo.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Find switches"].waitForExistence(timeout: 5))
        screenshot("03-real-mode-empty-state")
    }
    func testLargeTextAndLandscapeRemainNavigable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 15))
        screenshot("04-accessibility-text")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        screenshot("05-landscape-settings")
        app.buttons["Done"].tap()
    }
}
