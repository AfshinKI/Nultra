import Foundation

// A dependency-free executable check for Macs that only have Command Line Tools.
// XCTest coverage also lives under Tests/ for full Xcode/SwiftPM environments.
@main
struct ProtocolChecks {
    static func main() throws {
        var checks = 0
        func require(_ condition: Bool, _ message: String) {
            checks += 1
            guard condition else { fatalError(message) }
        }
        for raw in 0...255 {
            let data = Data([UInt8(raw)])
            let state = try? SwitchProtocol.power(data)
            require((state != nil) == (raw <= 1), "State accepted invalid byte \(raw)")
            let battery = try? SwitchProtocol.batteryPercent(data)
            require((battery != nil) == (raw <= 100), "Battery accepted invalid byte \(raw)")
        }
        require((try? SwitchProtocol.power(Data())) == nil, "Empty state accepted")
        require((try? SwitchProtocol.batteryPercent(Data())) == nil, "Empty battery accepted")
        for value in ["", "1234567", "123456789", "é2345678", "💡2345678", "1234\n678", "1234\u{0}678"] {
            require((try? SwitchProtocol.eightASCII(value)) == nil, "Invalid ASCII accepted")
        }
        require(try SwitchProtocol.eightASCII("DESKLAMP") == Data("DESKLAMP".utf8), "ASCII changed")
        let name = try SwitchProtocol.deviceName(Data(Array("DESKLAMP".utf8) + [1, 2, 255]))
        require(name.name == "DESKLAMP" && name.firmware == "v1.2.255", "Firmware decode failed")
        let padded = try SwitchProtocol.deviceName(Data([65, 66, 0, 0]))
        require(padded.name == "AB" && padded.firmware == nil, "Legacy name decode failed")
        require((try? SwitchProtocol.deviceName(Data([255]))) == nil, "Invalid UTF-8 accepted")
        require((try? SwitchProtocol.deviceName(Data())) == nil, "Empty name accepted")
        for on in 0...1 {
            for battery in 0...100 {
                let advertisement = String(format: "Nultra%d%03d", on, battery)
                let decoded = SwitchProtocol.advertisement(advertisement)
                require(decoded?.isOn == (on == 1) && decoded?.battery == battery, "Advertisement failed: \(advertisement)")
            }
        }
        for value in ["Nultra", "Nultra1999", "Nultra2092", "Nultra1-01", "Other1092"] {
            require(SwitchProtocol.advertisement(value) == nil, "Invalid advertisement accepted")
        }
        var device = SwitchDevice(id: UUID(), name: "DESKLAMP", rssi: -80)
        let first = Date(timeIntervalSince1970: 100)
        device.observe(localName: "Nultra1092", rssi: -50, at: first)
        require(device.isOn == true && device.battery == 92, "Initial broadcast missing")
        device.observe(localName: "Nultra0091", rssi: -60, at: first.addingTimeInterval(1))
        require(device.isOn == false && device.battery == 91, "Repeated broadcast not applied")
        require(device.name == "DESKLAMP" && device.lastConfirmed == nil, "Broadcast overwrote identity or confirmation")
        for value: String? in [nil, "Nultra1999"] {
            device.observe(localName: value, rssi: -70, at: first.addingTimeInterval(2))
            require(device.isOn == false && device.battery == 91, "Invalid packet overwrote state")
            require(device.lastBroadcast == first.addingTimeInterval(1), "Invalid packet refreshed broadcast age")
        }
        device.stateSource = .gatt
        device.lastConfirmed = first
        device.observe(localName: "Nultra1001", rssi: -40, at: first.addingTimeInterval(3), acceptsState: false)
        require(device.isOn == false && device.battery == 91 && device.stateSource == .gatt, "Broadcast replaced active GATT state")
        require(device.rssi == -40 && device.lastSeen == first.addingTimeInterval(3), "Presence not updated during GATT session")
        require(device.lastConfirmed == first, "Broadcast confirmed a command")
        print("Passed \(checks) protocol checks")
    }
}
