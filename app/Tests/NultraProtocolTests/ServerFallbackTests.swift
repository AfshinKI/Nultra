import XCTest
@testable import NultraProtocol

final class ServerFallbackTests: XCTestCase {
    let id = UUID()
    func row(_ address: String = "AA:BB:CC:DD:EE:01", _ name: String = "BEDROOM1", seen: Int = 1) throws -> ServerSwitch {
        let object: [String: Any] = ["address": address, "display_name": name, "seen_recently": seen, "switch_state": 1, "battery": 80]
        return try JSONDecoder().decode(ServerSwitch.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testConfigurationIsOptInAndSurvivesRelaunch() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defer { defaults.removeObject(forKey: ServerConfiguration.key) }
        XCTAssertFalse(ServerConfiguration.load(defaults: defaults).enabled)
        XCTAssertEqual(ServerConfiguration.load(defaults: defaults).address, "")
        let configuration = ServerConfiguration(enabled: true, address: "http://pi.local:5050", mappings: [id.uuidString: "AA:BB:CC:DD:EE:01"])
        configuration.save(defaults: defaults)
        XCTAssertEqual(ServerConfiguration.load(defaults: defaults), configuration)
    }
    func testURLValidation() throws {
        for url in ["http://192.168.1.2:5050", "https://lights.example.net/nultra", "http://[::1]:5050"] {
            XCTAssertNoThrow(try ServerConfiguration(address: url).baseURL())
        }
        for url in ["", "pi.local:5050", "file:///tmp/foo", "https://user:password@pi.local", "http://pi.local?x=1", "http://pi.local#x", "http://pi.local:99999"] {
            XCTAssertThrowsError(try ServerConfiguration(address: url).baseURL())
        }
    }
    func testUniqueNamesOnlyAndExplicitMappingSurvivesRename() throws {
        let device = KnownSwitch(id: id, name: "BEDROOM1")
        let first = try row()
        XCTAssertEqual(try ServerMapping.resolve(device, known: [device], rows: [first], configuration: .init()).address, first.address)
        let duplicate = try row("AA:BB:CC:DD:EE:02")
        XCTAssertThrowsError(try ServerMapping.resolve(device, known: [device], rows: [first, duplicate], configuration: .init()))
        XCTAssertThrowsError(try ServerMapping.resolve(device, known: [device, KnownSwitch(id: UUID(), name: device.name)], rows: [first], configuration: .init()))
        let renamed = try row("AA:BB:CC:DD:EE:02", "NEWNAME1")
        let mapped = ServerConfiguration(mappings: [id.uuidString: renamed.address])
        XCTAssertEqual(try ServerMapping.resolve(device, known: [device], rows: [first, renamed], configuration: mapped).address, renamed.address)
        // A stale explicit mapping must never fall back to a different address with the old name.
        XCTAssertThrowsError(try ServerMapping.resolve(device, known: [device], rows: [first], configuration: mapped))
    }
    func testOfflineOrMalformedSwitchCannotReceiveCommand() throws {
        let device = KnownSwitch(id: id, name: "BEDROOM1")
        for entry in [try row(seen: 0), try row(seen: -1), try row("../toggle_all/1"), try row("AA:BB:CC:DD:EE:01", "")] {
            XCTAssertThrowsError(try ServerMapping.resolve(device, known: [device], rows: [entry], configuration: .init()))
        }
    }
    func testClientUsesPerDeviceExplicitPowerAndRecognizesQueueRejection() async throws {
        MockServerProtocol.handler = { request in
            if request.httpMethod == "GET" {
                XCTAssertEqual(request.url?.path, "/nultra/devices")
                return (200, "[]")
            }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/nultra/toggle/AA:BB:CC:DD:EE:01/0")
            return (200, "{\"status\":\"ERROR\",\"message\":\"Queue unavailable\"}")
        }
        let client = try ServerClient(configuration: .init(enabled: true, address: "https://example.invalid/nultra"), protocolClasses: [MockServerProtocol.self])
        defer { client.close() }
        let rows = try await client.devices()
        XCTAssertTrue(rows.isEmpty)
        do { try await client.setPower(address: "AA:BB:CC:DD:EE:01", on: false); XCTFail("Rejected queue must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Queue unavailable")) }
    }
    func testClientRejectsHTTPFailureAndMalformedResponse() async throws {
        let client = try ServerClient(configuration: .init(address: "http://example.invalid"), protocolClasses: [MockServerProtocol.self])
        defer { client.close() }
        for reply in [(503, "[]"), (200, "<html>login</html>")] {
            MockServerProtocol.handler = { _ in reply }
            do { _ = try await client.devices(); XCTFail("Invalid response must fail") } catch { }
        }
        MockServerProtocol.handler = { _ in (200, "{\"status\":\"OK\"}") }
        try await client.setPower(address: "AA:BB:CC:DD:EE:01", on: true)
    }
}

private final class MockServerProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
