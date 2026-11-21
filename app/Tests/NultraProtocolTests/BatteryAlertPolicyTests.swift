import XCTest
@testable import NultraProtocol

final class BatteryAlertPolicyTests: XCTestCase {
    func testThresholdAndJitterDoNotRepeat() {
        var policy = BatteryAlertPolicy()
        XCTAssertFalse(policy.observe(6, threshold: 5))
        XCTAssertTrue(policy.observe(5, threshold: 5))
        for level in [4, 7, 3, 8, 5, 0, 14] { XCTAssertFalse(policy.observe(level, threshold: 5)) }
        XCTAssertFalse(policy.observe(15, threshold: 5))
        XCTAssertTrue(policy.observe(4, threshold: 5))
    }
    func testPersistenceAndThresholdChanges() throws {
        var policy = BatteryAlertPolicy()
        XCTAssertTrue(policy.observe(5, threshold: 5))
        var restored = try JSONDecoder().decode(BatteryAlertPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertFalse(restored.observe(5, threshold: 1))
        XCTAssertFalse(restored.observe(7, threshold: 50))
        XCTAssertFalse(restored.observe(15, threshold: 50))
        XCTAssertTrue(restored.observe(14, threshold: 50))
    }
    func testInvalidReadingsDoNotRearm() {
        var policy = BatteryAlertPolicy()
        for level in [nil, -1, 101] { XCTAssertFalse(policy.observe(level, threshold: 5)) }
        XCTAssertTrue(policy.observe(0, threshold: 5))
        XCTAssertFalse(policy.observe(101, threshold: 5))
        XCTAssertTrue(policy.alerted)
    }
}
