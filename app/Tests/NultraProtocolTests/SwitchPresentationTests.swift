import XCTest
@testable import NultraProtocol

final class SwitchPresentationTests: XCTestCase {
    func testFancySignalBoundaries() {
        for (rssi, bars) in [(127, 0), (-40, 3), (-60, 3), (-61, 2), (-80, 2), (-81, 1), (-100, 1)] {
            XCTAssertEqual(SwitchDevice(id: UUID(), name: "DESKLAMP", rssi: rssi).signalBars, bars)
        }
    }
    func testSignalIsThrottledWithoutDroppingStateOrPresence() {
        var device = SwitchDevice(id: UUID(), name: "DESKLAMP", rssi: 127)
        let time = Date(timeIntervalSince1970: 100)
        device.observe(localName: "Nultra1092", rssi: -50, at: time)
        device.observe(localName: "Nultra0091", rssi: -90, at: time.addingTimeInterval(4.9))
        XCTAssertEqual(device.signalBars, 3)
        XCTAssertEqual(device.isOn, false)
        XCTAssertEqual(device.battery, 91)
        XCTAssertEqual(device.lastSeen, time.addingTimeInterval(4.9))
        device.observe(localName: nil, rssi: -90, at: time.addingTimeInterval(5))
        XCTAssertEqual(device.signalBars, 1)
        XCTAssertEqual(device.isOn, false)
    }
    func testBatteryLowBoundaryAndSmallVisibleFill() {
        for level in [0, 1, 9, 10, 50, 100] {
            let device = SwitchDevice(id: UUID(), name: "DESKLAMP", rssi: -50, battery: level)
            XCTAssertEqual(device.batteryLow, level < 10)
            XCTAssertGreaterThanOrEqual(device.batteryFill, 0.08)
            XCTAssertLessThanOrEqual(device.batteryFill, 1)
        }
        XCTAssertEqual(SwitchDevice(id: UUID(), name: "DESKLAMP", rssi: 127).batteryFill, 0)
    }
    func testShortcutTargetsAllOrExplicitSavedIdentity() throws {
        let one = KnownSwitch(id: UUID(), name: "DESKLAMP", firmware: nil)
        let two = KnownSwitch(id: UUID(), name: "OFFICE01", firmware: nil)
        XCTAssertEqual(try SwitchAction.targets(requested: nil, known: [one, two]), [one.id, two.id])
        XCTAssertEqual(try SwitchAction.targets(requested: [two.id, two.id], known: [one, two]), [two.id])
        XCTAssertThrowsError(try SwitchAction.targets(requested: [UUID()], known: [one, two]))
        XCTAssertThrowsError(try SwitchAction.targets(requested: nil, known: []))
        XCTAssertThrowsError(try SwitchAction.targets(requested: [], known: [one]))
    }
}
