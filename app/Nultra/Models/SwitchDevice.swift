import Foundation

struct SwitchDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var battery: Int?
    var isOn: Bool?
    var firmware: String?
    var lastConfirmed: Date?
    var lastSeen: Date?
    var lastBroadcast: Date?
    var stateSource: StateSource = .unknown

    enum StateSource { case unknown, advertisement, gatt, demo }

    /// Only the local name in this packet may supply fresh state. CBPeripheral.name
    /// can be cached by iOS, so callers must not pass that fallback here.
    mutating func observe(localName: String?, rssi: Int, at date: Date, acceptsState: Bool = true) {
        self.rssi = rssi
        lastSeen = date
        guard acceptsState, let localName = localName,
              let broadcast = SwitchProtocol.advertisement(localName) else { return }
        isOn = broadcast.isOn
        battery = broadcast.battery
        lastBroadcast = date
        stateSource = .advertisement
    }

    var powerLabel: String { isOn.map { $0 ? "On" : "Off" } ?? "Unknown" }

    var batterySymbol: String {
        guard let battery = battery else { return "battery.0" }
        if battery >= 95 { return "battery.100" }
        if battery >= 75 { return "battery.75" }
        if battery >= 50 { return "battery.50" }
        if battery >= 10 { return "battery.25" }
        return "battery.0"
    }

    var signal: String {
        if rssi == 127 { return "Unknown signal" }
        if rssi >= -60 { return "Strong signal" }
        if rssi >= -80 { return "Good signal" }
        return "Weak signal"
    }
}
