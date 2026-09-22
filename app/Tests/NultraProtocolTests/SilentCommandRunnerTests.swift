import XCTest
@testable import NultraProtocol

final class SilentCommandRunnerTests: XCTestCase {
    @MainActor func testAcceptanceReturnsBeforeWorkCompletesAndRejectsOverlap() async throws {
        let runner = SilentCommandRunner()
        let started = expectation(description: "started")
        let completed = expectation(description: "completed")
        var resume: CheckedContinuation<Void, Never>?
        try runner.submit(operation: {
            await withCheckedContinuation { continuation in
                resume = continuation
                started.fulfill()
            }
        }, completion: { completed.fulfill() })
        XCTAssertTrue(runner.isRunning)
        XCTAssertThrowsError(try runner.submit(operation: {}, completion: {}))
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(runner.isRunning, "Acceptance must not wait for the operation")
        resume?.resume()
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertFalse(runner.isRunning)
    }

    @MainActor func testLateFailureIsSilentAndReleasesReservation() async throws {
        let runner = SilentCommandRunner()
        let finished = expectation(description: "failure cleaned up")
        try runner.submit(operation: { throw SwitchAction.Failure.interrupted },
                          completion: { finished.fulfill() })
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertFalse(runner.isRunning)
        let next = expectation(description: "next request")
        try runner.submit(operation: {}, completion: { next.fulfill() })
        await fulfillment(of: [next], timeout: 2)
    }

    @MainActor func testExpirationCancelsWorkAndCompletesExactlyOnce() async throws {
        let runner = SilentCommandRunner()
        let started = expectation(description: "started")
        let stopped = expectation(description: "stopped")
        var cleanupCount = 0
        try runner.submit(operation: {
            started.fulfill()
            try await Task.sleep(nanoseconds: 60_000_000_000)
            XCTFail("Expired work continued")
        }, completion: { cleanupCount += 1; stopped.fulfill() })
        await fulfillment(of: [started], timeout: 2)
        runner.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertFalse(runner.isRunning)
    }
}
