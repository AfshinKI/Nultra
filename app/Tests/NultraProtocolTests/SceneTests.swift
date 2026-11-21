import XCTest
@testable import NultraProtocol

final class SceneTests: XCTestCase {
    func testSharedMembershipAndUnknownTargetsNeverExpandToAll() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let first = SwitchScene(name: "Downstairs", members: [a, b, a, c])
        let second = SwitchScene(name: "Evening", members: [b])
        XCTAssertEqual(first.targets(known: [a, b]), [a, b])
        XCTAssertEqual(second.targets(known: [a, b]), [b])
        XCTAssertTrue(first.targets(known: []).isEmpty)
        XCTAssertThrowsError(try SwitchAction.targets(requested: [], known: [KnownSwitch(id: a, name: "LAMP0001", firmware: nil)]))
    }
    func testPersistenceRenameDeleteAndDefaultRefresh() {
        let suite = "nultra.scene-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = SceneCatalog(defaults: defaults)
        let member = UUID()
        var first = SwitchScene(name: "Living room", members: [member])
        let second = SwitchScene(name: "Evening", members: [member])
        catalog.save([first, second]); XCTAssertEqual(catalog.load(), [first, second])
        let id = first.id; first.name = "Downstairs"
        catalog.save([first, second]); XCTAssertEqual(catalog.load().first?.id, id)
        catalog.save([second]); XCTAssertEqual(catalog.load(), [second])
        let settings = RefreshSettings(defaults: defaults)
        XCTAssertTrue(settings.enabled); XCTAssertEqual(settings.minutes, 30)
        settings.enabled = false; settings.minutes = 15
        XCTAssertFalse(RefreshSettings(defaults: defaults).enabled)
        XCTAssertEqual(RefreshSettings(defaults: defaults).minutes, 15)
        settings.minutes = 1; XCTAssertEqual(settings.minutes, 30)
    }
}
