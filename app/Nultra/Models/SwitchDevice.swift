import Foundation

struct SwitchDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var battery: Int?
    var isOn: Bool?
    var firmware: String?
    var lastConfirmed: Date?
    var lastSeen: Date?
    var lastBroadcast: Date?
    var lastSignalSample: Date?
    var stateSource: StateSource = .unknown

    var identityKnown = false
    var lookupError: String?

    enum StateSource: Equatable { case unknown, advertisement, gatt, server, demo }

    /// Only the local name in this packet may supply fresh state. CBPeripheral.name
    /// can be cached by iOS, so callers must not pass that fallback here.
    mutating func observe(localName: String?, rssi: Int, at date: Date, acceptsState: Bool = true) {
        // Preserve every presence/state packet; sample only the decorative signal bars.
        if lastSignalSample == nil || date.timeIntervalSince(lastSignalSample!) >= 5 {
            self.rssi = rssi
            lastSignalSample = date
        }
        lastSeen = date
        guard acceptsState, let localName = localName,
              let broadcast = SwitchProtocol.advertisement(localName) else { return }
        isOn = broadcast.isOn
        battery = broadcast.battery
        lastBroadcast = date
        stateSource = .advertisement
    }

    static let presenceLifetime: TimeInterval = 15
    var visible: Bool { identityKnown && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func isOnline(at date: Date) -> Bool {
        guard let seen = lastSeen else { return false }
        let age = date.timeIntervalSince(seen)
        return age >= 0 && age < Self.presenceLifetime
    }

    var powerLabel: String { isOn.map { $0 ? "On" : "Off" } ?? "Unknown" }

    var batteryFill: Double {
        guard let battery = battery else { return 0 }
        return max(0.08, min(1, Double(battery) / 100))
    }
    var batteryLow: Bool { battery.map { $0 < 10 } ?? false }
    /// Same thresholds as fancy/webapp/app/static/js/icon.js.
    var signalBars: Int {
        if rssi == 127 { return 0 }
        return rssi >= -60 ? 3 : rssi >= -80 ? 2 : 1
    }

    var signal: String {
        if rssi == 127 { return "Unknown signal" }
        if rssi >= -60 { return "Strong signal" }
        if rssi >= -80 { return "Good signal" }
        return "Weak signal"
    }
}
