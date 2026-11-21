import Foundation

enum SwitchProtocol {
    static let service = "0000fe40-cc7a-482a-984a-7f2ed5b3e58f"
    static let state = "0000fe41-8e22-4541-9d4c-21edae82ed19"
    static let battery = "0000fe43-8e22-4541-9d4c-21edae82ed19"
    static let name = "0000fe44-8e22-4541-9d4c-21edae82ed19"
    static let password = "0000fe45-8e22-4541-9d4c-21edae82ed19"

    enum ProtocolError: LocalizedError {
        case invalidASCII, invalidState, invalidBattery, invalidName
        var errorDescription: String? {
            switch self {
            case .invalidASCII: return "Use exactly 8 ASCII characters. Emoji and accented characters are not supported."
            case .invalidState: return "The switch returned an invalid power state. Reconnect and try again."
            case .invalidBattery: return "The switch returned an invalid battery reading."
            case .invalidName: return "The switch returned an empty or unreadable name."
            }
        }
    }

    static func eightASCII(_ value: String) throws -> Data {
        guard let data = value.data(using: .ascii), data.count == 8,
              data.allSatisfy({ $0 >= 32 && $0 <= 126 }) else {
            throw ProtocolError.invalidASCII
        }
        return data
    }

    static func power(_ data: Data) throws -> Bool {
        guard let byte = data.first, byte <= 1 else { throw ProtocolError.invalidState }
        return byte == 1
    }

    static func batteryPercent(_ data: Data) throws -> Int {
        guard let byte = data.first, byte <= 100 else { throw ProtocolError.invalidBattery }
        return Int(byte)
    }

    static func deviceName(_ data: Data) throws -> (name: String, firmware: String?) {
        let bytes = Array(data)
        let nameBytes = bytes.count == 11 ? Array(bytes.prefix(8)) : bytes
        guard let decoded = String(bytes: nameBytes, encoding: .utf8) else {
            throw ProtocolError.invalidName
        }
        let name = decoded.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
        guard !name.isEmpty else { throw ProtocolError.invalidName }
        let firmware = bytes.count == 11 ? "v\(bytes[8]).\(bytes[9]).\(bytes[10])" : nil
        return (name, firmware)
    }

    static func advertisement(_ name: String) -> (isOn: Bool, battery: Int)? {
        let bytes = Array(name.utf8)
        guard bytes.count >= 10, Array(bytes.prefix(6)) == Array("Nultra".utf8),
              bytes[6] == 48 || bytes[6] == 49,
              bytes[7...9].allSatisfy({ (48...57).contains($0) }) else { return nil }
        let battery = Int(bytes[7] - 48) * 100 + Int(bytes[8] - 48) * 10 + Int(bytes[9] - 48)
        guard battery <= 100 else { return nil }
        return (bytes[6] == 49, battery)
    }
}
