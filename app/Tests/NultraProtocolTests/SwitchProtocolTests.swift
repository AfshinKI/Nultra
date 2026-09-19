import XCTest
@testable import NultraProtocol

final class SwitchProtocolTests: XCTestCase {
    func testPowerRequiresValidByte() throws {
        XCTAssertFalse(try SwitchProtocol.power(Data([0])))
        XCTAssertTrue(try SwitchProtocol.power(Data([1])))
        XCTAssertThrowsError(try SwitchProtocol.power(Data()))
        XCTAssertThrowsError(try SwitchProtocol.power(Data([2])))
        XCTAssertThrowsError(try SwitchProtocol.power(Data([255])))
    }

    func testBatteryBounds() throws {
        XCTAssertEqual(try SwitchProtocol.batteryPercent(Data([0])), 0)
        XCTAssertEqual(try SwitchProtocol.batteryPercent(Data([100])), 100)
        XCTAssertThrowsError(try SwitchProtocol.batteryPercent(Data([101])))
        XCTAssertThrowsError(try SwitchProtocol.batteryPercent(Data()))
    }

    func testASCIIUsesByteLengthAndRejectsLossyEncoding() throws {
        XCTAssertEqual(try SwitchProtocol.eightASCII("DESKLAMP"), Data("DESKLAMP".utf8))
        for invalid in ["short", "TOO-LONG!", "CaféLamp", "💡💡💡💡💡💡💡💡", "ABCD\n123", "ABCD\u{0}123"] {
            XCTAssertThrowsError(try SwitchProtocol.eightASCII(invalid), invalid)
        }
    }

    func testNameAndFirmwareDecoding() throws {
        let decoded = try SwitchProtocol.deviceName(Data(Array("DESKLAMP".utf8) + [2, 1, 17]))
        XCTAssertEqual(decoded.name, "DESKLAMP")
        XCTAssertEqual(decoded.firmware, "v2.1.17")
        let legacy = try SwitchProtocol.deviceName(Data("Switch".utf8))
        XCTAssertEqual(legacy.name, "Switch")
        XCTAssertNil(legacy.firmware)
        XCTAssertEqual(try SwitchProtocol.deviceName(Data([65, 66, 0, 0])).name, "AB")
        XCTAssertThrowsError(try SwitchProtocol.deviceName(Data()))
        XCTAssertThrowsError(try SwitchProtocol.deviceName(Data([255])))
    }

    func testAdvertisementParsing() {
        XCTAssertEqual(SwitchProtocol.advertisement("Nultra1092")?.battery, 92)
        XCTAssertEqual(SwitchProtocol.advertisement("Nultra1092")?.isOn, true)
        XCTAssertEqual(SwitchProtocol.advertisement("Nultra0100")?.isOn, false)
        XCTAssertEqual(SwitchProtocol.advertisement("Nultra0000")?.battery, 0)
        for invalid in ["Nultra", "Nultra1999", "Nultra2abc", "Other1092", "Nultra2092", "Nultra1-01"] {
            XCTAssertNil(SwitchProtocol.advertisement(invalid), invalid)
        }
    }
}
