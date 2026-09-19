import XCTest

final class NultraUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDemoControlRenameAndDisconnect() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["demo.banner"].waitForExistence(timeout: 15))
        screenshot("01-dashboard-13-mini")
        let card = app.buttons["device.DESKLAMP"]
        if !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["Try this switch"].waitForExistence(timeout: 5))
        app.buttons["Try this switch"].tap()
        XCTAssertTrue(app.buttons["power.off"].waitForExistence(timeout: 5))
        app.buttons["power.off"].tap()
        XCTAssertEqual(app.staticTexts["power.state"].label, "Power is off")
        app.buttons["power.on"].tap()
        XCTAssertEqual(app.staticTexts["power.state"].label, "Power is on")
        screenshot("02-connected-switch")
        app.buttons["Rename"].tap()
        let field = app.textFields["rename.field"]
        if !field.isHittable { app.swipeUp() }
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "BEDROOM1")
        let save = app.buttons["Save name"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["BEDROOM1"].waitForExistence(timeout: 5))
        let disconnect = app.buttons["Disconnect"]
        if !disconnect.isHittable { app.swipeDown() }
        disconnect.tap()
        XCTAssertTrue(app.buttons["Try this switch"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.swipeDown()
        app.buttons["settings"].tap()
        let toggle = app.switches["demo.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Find switches"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.banner"].exists)
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
