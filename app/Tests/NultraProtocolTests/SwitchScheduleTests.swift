import XCTest
@testable import NultraProtocol

final class SwitchScheduleTests: XCTestCase {
    func testThreeParallelSlotsAndReleaseOnlyAfterAcknowledgement() {
        var queue = SwitchSchedule(limit: 3)
        let ids = (0..<6).map { _ in UUID() }
        ids.forEach { queue.enqueue(SwitchRequest(id: $0, operation: .power(true))) }
        let first = queue.takeNext()!
        _ = queue.takeNext(); _ = queue.takeNext()
        XCTAssertEqual(queue.active.count, 3)
        XCTAssertNil(queue.takeNext())
        XCTAssertFalse(queue.enqueue(SwitchRequest(id: first.id, operation: .power(false))))
        // A transaction asking to disconnect does not free its scheduler slot.
        var transaction = SwitchTransaction(operation: first.operation)
        _ = transaction.handle(.cancel)
        XCTAssertNil(queue.takeNext())
        _ = transaction.handle(.disconnected)
        queue.finished(first.id)
        XCTAssertEqual(queue.takeNext()?.id, ids[3])
        XCTAssertEqual(queue.active.count, 3)
    }
    func testUserCommandsPrecedeIdentificationAndCancellationKeepsActiveSlots() {
        var queue = SwitchSchedule(limit: 3)
        let automatic = UUID(), user = UUID()
        queue.enqueue(SwitchRequest(id: automatic, operation: .identify, automatic: true))
        queue.enqueue(SwitchRequest(id: user, operation: .power(false)))
        XCTAssertEqual(queue.takeNext()?.id, user)
        XCTAssertEqual(queue.cancelPending().map(\.id), [automatic])
        XCTAssertEqual(queue.active, [user])
        XCTAssertTrue(queue.hasWork)
        queue.finished(user)
        XCTAssertFalse(queue.hasWork)
    }
    func testBulkResultsCountEachTargetOnceIncludingFailures() {
        let first = UUID(), second = UUID()
        var progress = BulkProgress(ids: [first, second])
        progress.finish(first, success: true)
        XCTAssertFalse(progress.complete)
        progress.finish(first, success: false)
        progress.finish(UUID(), success: true)
        progress.finish(second, success: false)
        XCTAssertTrue(progress.complete)
        XCTAssertEqual(progress.results.count, 2)
        XCTAssertEqual(progress.message, "1/2 updated · 1 unsuccessful")
    }
    func testPresenceExpiryDoesNotRemoveNamedSwitch() {
        let instant = Date(timeIntervalSince1970: 100)
        var device = SwitchDevice(id: UUID(), name: "DESKLAMP", rssi: -50, identityKnown: true)
        XCTAssertFalse(device.isOnline(at: instant))
        device.observe(localName: "Nultra1092", rssi: -50, at: instant)
        XCTAssertTrue(device.isOnline(at: instant))
        XCTAssertTrue(device.isOnline(at: instant.addingTimeInterval(14.9)))
        XCTAssertFalse(device.isOnline(at: instant.addingTimeInterval(15)))
        XCTAssertTrue(device.visible)
        XCTAssertEqual(device.name, "DESKLAMP")
        var candidate = SwitchDevice(id: UUID(), name: "Nultra1092", rssi: -50)
        XCTAssertFalse(candidate.visible)
        candidate.identityKnown = true; candidate.name = "   "
        XCTAssertFalse(candidate.visible)
    }
    func testCatalogRestoresRealNamesAcrossInstancesAndUpdatesRename() {
        let suite = "nultra.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SwitchCatalog(defaults: defaults)
        let id = UUID()
        first.save(KnownSwitch(id: id, name: "DESKLAMP", firmware: "v1.0.0"))
        first.save(KnownSwitch(id: UUID(), name: " ", firmware: nil))
        let reopened = SwitchCatalog(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reopened.load(), [KnownSwitch(id: id, name: "DESKLAMP", firmware: "v1.0.0")])
        reopened.save(KnownSwitch(id: id, name: "OFFICE01", firmware: "v1.0.0"))
        XCTAssertEqual(first.load().count, 1)
        XCTAssertEqual(first.load().first?.name, "OFFICE01")
    }
    func testParallelTransactionsCannotConfirmEachOther() {
        var first = SwitchTransaction(operation: .power(true))
        var second = SwitchTransaction(operation: .rename("OFFICE01"))
        for event: SwitchTransaction.Event in [.connected, .prepared, .authenticated] {
            _ = first.handle(event); _ = second.handle(event)
        }
        _ = first.handle(.powerSent); _ = second.handle(.nameWritten)
        XCTAssertNil(first.handle(.nameRead("OFFICE01", nil)))
        XCTAssertNil(second.handle(.powerRead(true)))
        XCTAssertEqual(first.handle(.powerRead(true)), .disconnect)
        XCTAssertEqual(second.stage, .reading)
        XCTAssertEqual(second.handle(.nameRead("OFFICE01", nil)), .disconnect)
    }
}
