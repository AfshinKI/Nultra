import Foundation

struct ServerConfiguration: Codable, Equatable {
    var enabled = false
    var address = ""
    var mappings: [String: String] = [:]
    static let key = "nultra.server-fallback.v1"
    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
    func baseURL() throws -> URL {
        guard let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.port == nil || (1...65535).contains(parts.port!), let url = parts.url else {
            throw ServerFailure.message("Enter a full http:// or https:// server URL, including its port if needed. Do not include a username, password, query, or fragment.")
        }
        return url
    }
}

struct ServerSwitch: Decodable, Identifiable, Equatable {
    let address: String
    let display_name: String
    let seen_recently: Int
    let switch_state: Int?
    let battery: Int?
    var id: String { address }
    var name: String { display_name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var available: Bool { seen_recently == 1 }
    var validAddress: Bool { address.range(of: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$", options: .regularExpression) != nil }
}

enum ServerFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum ServerMapping {
    static func resolve(_ device: KnownSwitch, known: [KnownSwitch], rows: [ServerSwitch], configuration: ServerConfiguration) throws -> ServerSwitch {
        let candidates: [ServerSwitch]
        if let address = configuration.mappings[device.id.uuidString] {
            candidates = rows.filter { $0.address == address }
        } else {
            guard known.filter({ $0.name == device.name }).count == 1 else {
                throw ServerFailure.message("Multiple saved switches are named \(device.name). Select its server mapping in Menu.")
            }
            candidates = rows.filter { $0.name == device.name }
        }
        guard candidates.count == 1, let match = candidates.first, match.validAddress, !match.name.isEmpty else {
            throw ServerFailure.message("No unique server match for \(device.name). Check switch mapping in Menu.")
        }
        guard match.available else { throw ServerFailure.message("The server has not seen \(device.name) recently.") }
        return match
    }
}

/// Fancy acknowledges queue admission, NOT completion. Never treat an OK as GATT readback.
final class ServerClient: NSObject, URLSessionTaskDelegate {
    private let base: URL
    private var session: URLSession!
    init(configuration: ServerConfiguration, protocolClasses: [AnyClass]? = nil) throws {
        // The historical gateway sent no authentication. Keep protocol-fixture tests available.
        guard let classes = protocolClasses, !classes.isEmpty else { throw URLError(.userAuthenticationRequired) }
        base = try configuration.baseURL()
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.protocolClasses = protocolClasses
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    func close() { session.invalidateAndCancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // A proxy/login redirect must never turn a command into an unrelated request.
    }
    private func request(_ components: [String], method: String = "GET") async throws -> Data {
        var url = base
        for component in components { url.appendPathComponent(component) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServerFailure.message("Server request failed. Check the address, port, and network access.")
        }
        return data
    }
    func devices() async throws -> [ServerSwitch] {
        try JSONDecoder().decode([ServerSwitch].self, from: await request(["devices"]))
    }
    func setPower(address: String, on: Bool) async throws {
        guard address.range(of: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$", options: .regularExpression) != nil else {
            throw ServerFailure.message("Invalid server switch address.")
        }
        struct Reply: Decodable { let status: String; let message: String? }
        let reply = try JSONDecoder().decode(Reply.self, from: await request(["toggle", address, on ? "1" : "0"], method: "POST"))
        guard reply.status == "OK" else { throw ServerFailure.message(reply.message ?? "Server rejected the command.") }
    }
}
