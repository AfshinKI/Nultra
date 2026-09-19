import Foundation

/// A single connection has exactly one purpose. No state allows an idle connection.
struct SwitchTransaction {
    enum Operation: Equatable { case identify, power(Bool), rename(String) }
    enum Stage: Equatable {
        case connecting, discovering, authenticating, waitingToWrite, writingName, reading, disconnecting, finished
        var label: String {
            switch self {
            case .connecting: return "Connecting…"
            case .discovering: return "Finding service…"
            case .authenticating: return "Authenticating…"
            case .waitingToWrite, .writingName: return "Updating…"
            case .reading: return "Verifying…"
            case .disconnecting: return "Disconnecting…"
            case .finished: return "Disconnected"
            }
        }
    }
    enum Event {
        case connected, prepared, authenticated, powerSent, nameWritten
        case nameRead(String, String?), powerRead(Bool)
        case failed(String), timeout, cancel, disconnected
    }
    enum Effect: Equatable {
        case discover, authenticate, writePower(Bool), writeName(String), readName, readPower, disconnect
    }
    enum Result: Equatable { case identity(String, String?), power(Bool) }

    let operation: Operation
    private(set) var stage: Stage = .connecting
    private(set) var result: Result?
    private(set) var failure: String?

    mutating func handle(_ event: Event) -> Effect? {
        // Cancellation is terminal until the transport acknowledges disconnection.
        if case .disconnected = event {
            if stage != .disconnecting && stage != .finished { failure = "The switch disconnected before finishing." }
            stage = .finished
            return nil
        }
        guard stage != .disconnecting && stage != .finished else { return nil }
        switch event {
        case .failed(let message): return stop(message)
        case .timeout: return stop("The switch did not finish in time. Move closer and retry.")
        case .cancel: return stop(nil)
        default: break
        }
        switch (stage, event) {
        case (.connecting, .connected):
            stage = .discovering; return .discover
        case (.discovering, .prepared):
            stage = .authenticating; return .authenticate
        case (.authenticating, .authenticated):
            switch operation {
            case .identify: stage = .reading; return .readName
            case .power(let value): stage = .waitingToWrite; return .writePower(value)
            case .rename(let name): stage = .writingName; return .writeName(name)
            }
        case (.waitingToWrite, .powerSent):
            stage = .reading; return .readPower
        case (.writingName, .nameWritten):
            stage = .reading; return .readName
        case (.reading, .nameRead(let name, let firmware)):
            switch operation {
            case .identify: break
            case .rename(let expected):
                guard name == expected.trimmingCharacters(in: .whitespaces) else {
                    return stop("The switch did not confirm its new name.")
                }
            case .power: return nil
            }
            result = .identity(name, firmware)
            return stop(nil)
        case (.reading, .powerRead(let value)):
            guard case .power(let expected) = operation else { return nil }
            guard value == expected else { return stop("The requested power state was not confirmed.") }
            result = .power(value)
            return stop(nil)
        default: return nil
        }
    }

    private mutating func stop(_ message: String?) -> Effect {
        failure = message
        stage = .disconnecting
        return .disconnect
    }
}

struct KnownSwitch: Codable, Equatable {
    let id: UUID
    var name: String
    var firmware: String?
}
