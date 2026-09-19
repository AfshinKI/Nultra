import XCTest
@testable import NultraProtocol

final class SwitchTransactionTests: XCTestCase {
    private func authenticated(_ operation: SwitchTransaction.Operation) -> SwitchTransaction {
        var state = SwitchTransaction(operation: operation)
        XCTAssertEqual(state.handle(.connected), .discover)
        XCTAssertEqual(state.handle(.prepared), .authenticate)
        return state
    }

    func testIdentificationReadsOnlyNameAndImmediatelyDisconnects() {
        var state = authenticated(.identify)
        XCTAssertEqual(state.handle(.authenticated), .readName)
        XCTAssertEqual(state.handle(.nameRead("DESKLAMP", "v1.2.3")), .disconnect)
        XCTAssertEqual(state.result, .identity("DESKLAMP", "v1.2.3"))
        XCTAssertEqual(state.stage, .disconnecting)
        XCTAssertNil(state.handle(.authenticated))
        XCTAssertNil(state.handle(.disconnected))
        XCTAssertEqual(state.stage, .finished)
    }

    func testPowerBothDirectionsWriteReadAndDisconnectWithoutMetadataReads() {
        for value in [false, true] {
            var state = authenticated(.power(value))
            XCTAssertEqual(state.handle(.authenticated), .writePower(value))
            XCTAssertNil(state.handle(.authenticated), "Duplicate auth must not write twice")
            XCTAssertEqual(state.handle(.powerSent), .readPower)
            XCTAssertNil(state.handle(.powerSent), "Flow-control callback must not duplicate write/read")
            XCTAssertEqual(state.handle(.powerRead(value)), .disconnect)
            XCTAssertEqual(state.result, .power(value))
            XCTAssertEqual(state.stage, .disconnecting)
            XCTAssertNil(state.failure)
        }
    }

    func testRenameWaitsForWriteAcknowledgementThenVerifiesAndDisconnects() {
        var state = authenticated(.rename("BEDROOM1"))
        XCTAssertEqual(state.handle(.authenticated), .writeName("BEDROOM1"))
        XCTAssertNil(state.handle(.nameRead("BEDROOM1", nil)), "Unsolicited read cannot confirm write")
        XCTAssertEqual(state.handle(.nameWritten), .readName)
        XCTAssertEqual(state.handle(.nameRead("BEDROOM1", "v1.0.0")), .disconnect)
        XCTAssertEqual(state.result, .identity("BEDROOM1", "v1.0.0"))
    }

    func testReadbackMismatchDisconnectsAndDoesNotPublishSuccess() {
        var power = authenticated(.power(true))
        _ = power.handle(.authenticated); _ = power.handle(.powerSent)
        XCTAssertEqual(power.handle(.powerRead(false)), .disconnect)
        XCTAssertNotNil(power.failure); XCTAssertNil(power.result)
        var name = authenticated(.rename("BEDROOM1"))
        _ = name.handle(.authenticated); _ = name.handle(.nameWritten)
        XCTAssertEqual(name.handle(.nameRead("OLDNAME1", nil)), .disconnect)
        XCTAssertNotNil(name.failure); XCTAssertNil(name.result)
    }

    func testTimeoutFailureAndBackgroundCancellationDisconnectAtEveryLiveStage() {
        let paths: [(SwitchTransaction.Operation, [SwitchTransaction.Event])] = [
            (.identify, []), (.identify, [.connected]), (.identify, [.connected, .prepared]),
            (.identify, [.connected, .prepared, .authenticated]),
            (.power(true), [.connected, .prepared, .authenticated]),
            (.power(true), [.connected, .prepared, .authenticated, .powerSent]),
            (.rename("BEDROOM1"), [.connected, .prepared, .authenticated]),
            (.rename("BEDROOM1"), [.connected, .prepared, .authenticated, .nameWritten])
        ]
        for (operation, path) in paths {
            for terminal: SwitchTransaction.Event in [.timeout, .cancel, .failed("Transport error")] {
                var state = SwitchTransaction(operation: operation)
                path.forEach { _ = state.handle($0) }
                XCTAssertEqual(state.handle(terminal), .disconnect)
                XCTAssertEqual(state.stage, .disconnecting)
                XCTAssertNil(state.result)
                for late: SwitchTransaction.Event in [.connected, .prepared, .authenticated, .powerSent, .nameWritten, .powerRead(true), .nameRead("BEDROOM1", nil), .timeout] {
                    XCTAssertNil(state.handle(late), "Late event must never extend a cancelled transaction")
                }
                XCTAssertEqual(state.stage, .disconnecting, "Wait for transport cancellation acknowledgement")
                _ = state.handle(.disconnected)
                XCTAssertEqual(state.stage, .finished)
                XCTAssertNil(state.handle(.connected))
            }
        }
    }

    func testUnexpectedDisconnectDoesNotRetry() {
        var state = authenticated(.power(true))
        XCTAssertNil(state.handle(.disconnected))
        XCTAssertEqual(state.stage, .finished)
        XCTAssertNotNil(state.failure)
        XCTAssertNil(state.handle(.authenticated))
    }

    func testKnownNamesSurviveCatalogRoundTrip() throws {
        let identity = KnownSwitch(id: UUID(), name: "DESKLAMP", firmware: "v1.2.3")
        let encoded = try JSONEncoder().encode([identity])
        XCTAssertEqual(try JSONDecoder().decode([KnownSwitch].self, from: encoded), [identity])
    }
}
