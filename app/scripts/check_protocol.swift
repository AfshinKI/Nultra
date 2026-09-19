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
        require(device.rssi == -50 && device.lastSeen == first.addingTimeInterval(3), "Presence must update while decorative signal strength is throttled")
        require(device.lastConfirmed == first, "Broadcast confirmed a command")
        for operation: SwitchTransaction.Operation in [.identify, .power(false), .power(true), .rename("BEDROOM1")] {
            var tx = SwitchTransaction(operation: operation)
            var liveStates = [tx]
            require(tx.handle(.connected) == .discover, "Missing service discovery")
            liveStates.append(tx)
            require(tx.handle(.prepared) == .authenticate, "Missing authentication")
            liveStates.append(tx)
            let authenticatedEffect = tx.handle(.authenticated)
            liveStates.append(tx)
            switch operation {
            case .identify:
                require(authenticatedEffect == .readName, "Identification read extra data")
                require(tx.handle(.nameRead("DESKLAMP", "v1.2.3")) == .disconnect, "Identification held connection")
            case .power(let value):
                require(authenticatedEffect == .writePower(value), "Wrong power target")
                require(tx.handle(.powerSent) == .readPower, "Missing power verification")
                liveStates.append(tx)
                require(tx.handle(.powerRead(value)) == .disconnect, "Power held connection")
            case .rename(let name):
                require(authenticatedEffect == .writeName(name), "Wrong rename target")
                require(tx.handle(.nameWritten) == .readName, "Missing rename verification")
                liveStates.append(tx)
                require(tx.handle(.nameRead(name, nil)) == .disconnect, "Rename held connection")
            }
            require(tx.stage == .disconnecting && tx.result != nil, "Completion missing cancellation")
            require(tx.handle(.authenticated) == nil, "Late callback restarted write")
            _ = tx.handle(.disconnected)
            require(tx.stage == .finished, "Disconnect not completed")
            for state in liveStates {
                for event: SwitchTransaction.Event in [.timeout, .cancel, .failed("transport")] {
                    var cancelled = state
                    require(cancelled.handle(event) == .disconnect, "Failure left connection open")
                    for late: SwitchTransaction.Event in [.connected, .prepared, .authenticated, .powerSent, .nameWritten, .powerRead(true), .nameRead("BEDROOM1", nil)] {
                        require(cancelled.handle(late) == nil, "Cancelled transaction performed work")
                    }
                    require(cancelled.stage == .disconnecting, "Did not wait for cancellation acknowledgement")
                }
            }
        }
        let ids = (0..<7).map { _ in UUID() }
        var schedule = SwitchSchedule(limit: 3)
        ids.forEach { schedule.enqueue(SwitchRequest(id: $0, operation: .power(true))) }
        for _ in 0..<3 { require(schedule.takeNext() != nil, "Parallel slot unavailable") }
        require(schedule.takeNext() == nil && schedule.active.count == 3, "Parallel limit exceeded")
        require(!schedule.enqueue(SwitchRequest(id: ids[0], operation: .power(false))), "Duplicate active request accepted")
        schedule.finished(ids[1])
        require(schedule.takeNext()?.id == ids[3], "Released slot did not advance queue")
        require(schedule.cancelPending().count == 3 && schedule.active.count == 3, "Cancellation released active transport early")
        var presence = SwitchDevice(id: UUID(), name: "DESKLAMP", rssi: -50, identityKnown: true)
        let instant = Date(timeIntervalSince1970: 100)
        require(!presence.isOnline(at: instant), "Unseen saved switch marked online")
        presence.observe(localName: "Nultra1092", rssi: -50, at: instant)
        require(presence.isOnline(at: instant.addingTimeInterval(14)), "Recent packet marked offline")
        require(!presence.isOnline(at: instant.addingTimeInterval(15)) && presence.visible, "Expiry removed switch or retained online state")
        require(!SwitchDevice(id: UUID(), name: "Nultra1092", rssi: -50).visible, "Unnamed device displayed")
        var bulk = BulkProgress(ids: [ids[0], ids[1]])
        bulk.finish(ids[0], success: true); bulk.finish(ids[0], success: false)
        require(!bulk.complete && bulk.results.count == 1, "Duplicate bulk result counted")
        bulk.finish(ids[1], success: false)
        require(bulk.complete && bulk.message == "1/2 updated · 1 unsuccessful", "Partial bulk failure lost")
        print("Passed \(checks) protocol checks")
    }
}
