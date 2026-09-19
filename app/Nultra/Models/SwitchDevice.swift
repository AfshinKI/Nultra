import Foundation

struct SwitchDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var battery: Int?
    var isOn: Bool?
    var firmware: String?
    var lastConfirmed: Date?

    var signal: String {
        if rssi == 127 { return "Unknown signal" }
        if rssi >= -60 { return "Strong signal" }
        if rssi >= -80 { return "Good signal" }
        return "Weak signal"
    }
}
