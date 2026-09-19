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
        XCTAssertFalse(app.buttons["device.UNNAMED"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["presence.HALLWAY1"].label, "Offline")
        XCTAssertEqual(app.descendants(matching: .any)["presence.DESKLAMP"].label, "Online")
        XCTAssertFalse(app.staticTexts["92%"].exists, "Battery percentage belongs in details only")
        XCTAssertFalse(app.staticTexts["-48"].exists, "Dashboard uses signal bars")
        XCTAssertEqual(app.descendants(matching: .any)["signal.DESKLAMP"].label, "Signal 3 of 3 bars")
        XCTAssertLessThan(app.buttons["toggle.SHELFLED"].frame.maxY, 500, "Compact cards should fit well within the mini screen")
        screenshot("01-dashboard-13-mini")
        app.buttons["all.off"].tap()
        XCTAssertTrue(app.buttons["toggle.DESKLAMP"].label.contains("Off"))
        XCTAssertTrue(app.buttons["toggle.KITCHEN1"].label.contains("Off"))
        app.buttons["all.on"].tap()
        XCTAssertTrue(app.buttons["toggle.DESKLAMP"].label.contains("On"))
        XCTAssertTrue(app.buttons["toggle.HALLWAY1"].label.contains("On"))
        app.buttons["toggle.DESKLAMP"].tap()
        XCTAssertTrue(app.buttons["toggle.DESKLAMP"].label.contains("Off"))
        app.buttons["device.DESKLAMP"].tap()
        XCTAssertTrue(app.staticTexts["connection.status"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["connection.status"].label, "Disconnected")
        app.switches["power.toggle"].tap()
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
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        for _ in 0..<4 { if toggle.isHittable { break }; app.swipeUp() }
        toggle.tap()
        app.buttons["Done"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if permission.waitForExistence(timeout: 2) { permission.tap() }
        XCTAssertTrue(app.staticTexts["scan.status"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Find switches"].exists)
        screenshot("03-real-mode-empty-state")
    }
    func testBusyCardShowsOnlyProgress() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--busy-demo"]; app.launch()
        XCTAssertTrue(app.buttons["toggle.DESKLAMP"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["toggle.DESKLAMP"].label, "Updating DESKLAMP")
        XCTAssertFalse(app.staticTexts["Connecting…"].exists)
        XCTAssertFalse(app.staticTexts["Authenticating…"].exists)
        XCTAssertFalse(app.buttons["toggle.DESKLAMP"].isEnabled)
        screenshot("07-spinner-only")
    }
    func testShortcutRejectsDemoWithoutClaimingRealSuccess() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--test-shortcut-all-off"]; app.launch()
        let alert = app.alerts["Switch needs attention"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["Turn off demo mode in Nultra before running a switch shortcut."].exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["toggle.DESKLAMP"].label.contains("On"))
    }
    func testSwitchPasswordRequiresExplicitSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.secureTextFields["master.password"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["master.save"].isEnabled)
}
    func testBackupServerConfigurationPersistsWithoutContactInDemo() throws {
        let app = launchDemo()
        app.buttons["settings"].tap()
        let field = app.textFields["server.address"]
        for _ in 0..<4 { if field.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(field.isHittable)
        field.tap()
        if let value = field.value as? String, value.hasPrefix("http") {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText("http://example.invalid:5050")
        let save = app.buttons["server.save"]
        for _ in 0..<3 { if save.isHittable { break }; app.swipeUp() }
        save.tap()
        app.terminate(); app.launch()
        app.buttons["settings"].tap()
        for _ in 0..<4 { if field.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(field.value as? String, "http://example.invalid:5050")
        XCTAssertFalse(app.buttons["server.check"].isEnabled, "Demo cannot contact the real server")
        screenshot("08-backup-server-settings")
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
