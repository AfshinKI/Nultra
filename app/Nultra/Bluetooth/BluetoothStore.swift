import Foundation
import Combine
import CoreBluetooth

/// All CoreBluetooth callbacks and UI actions execute on the main queue.
/// One active peripheral keeps writes serialized and reduces contention with the Pi.
final class BluetoothStore: NSObject, ObservableObject {
    @Published private(set) var devices: [SwitchDevice] = []
    @Published private(set) var scanning = false
    @Published private(set) var radio = "Ready when you are"
    @Published private(set) var activeID: UUID?
    @Published private(set) var phase = Phase.idle
    @Published private(set) var demo = false
    @Published var errorMessage: String?

    enum Phase: Equatable {
        case idle, connecting, discovering, authenticating, loading, ready, changing, renaming, refreshing, disconnecting
        var label: String {
            switch self {
            case .idle: return "Nearby"
            case .connecting: return "Connecting…"
            case .discovering: return "Finding services…"
            case .authenticating: return "Sending password…"
            case .loading: return "Reading switch…"
            case .ready: return "Connected"
            case .changing: return "Confirming power…"
            case .renaming: return "Confirming name…"
            case .refreshing: return "Refreshing…"
            case .disconnecting: return "Disconnecting…"
            }
        }
    }

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var current: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var password: Data?
    private var reads = Set<CBUUID>()
    private var targetPower: Bool?
    private var targetName: String?
    private var writeQueued = false
    private var deadline: DispatchWorkItem?
    private var scanWhenReady = false
    private let credentials = CredentialStore()

    private let serviceID = CBUUID(string: SwitchProtocol.service)
    private let stateID = CBUUID(string: SwitchProtocol.state)
    private let batteryID = CBUUID(string: SwitchProtocol.battery)
    private let nameID = CBUUID(string: SwitchProtocol.name)
    private let passwordID = CBUUID(string: SwitchProtocol.password)

    func startScan() {
        guard !demo else { return }
        if central == nil {
            scanWhenReady = true
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        guard central?.state == .poweredOn else {
            errorMessage = radio
            return
        }
        stopScan()
        // Keep known names and last observations across scans. The UI labels
        // those values as last observed, never as proof a switch is reachable.
        scanning = true
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        scanWhenReady = false
        central?.stopScan()
        scanning = false
    }

    func savedPasswordExists(for id: UUID) -> Bool {
        do { return try credentials.read(id) != nil }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func connect(_ id: UUID, enteredPassword: String? = nil) {
        guard activeID == nil else { return }
        if demo { activeID = id; phase = .ready; return }
        guard central?.state == .poweredOn, let peripheral = peripherals[id] else {
            errorMessage = "Scan again to find this switch."
            return
        }
        do {
            if let enteredPassword = enteredPassword {
                let data = try SwitchProtocol.eightASCII(enteredPassword)
                try credentials.save(data, for: id)
                password = data
            } else {
                guard let data = try credentials.read(id), data.count == 8 else {
                    errorMessage = "Enter this switch’s eight-character password."
                    return
                }
                password = data
            }
        } catch { errorMessage = error.localizedDescription; return }
        errorMessage = nil
        current = peripheral
        activeID = id
        characteristics.removeAll()
        peripheral.delegate = self
        phase = .connecting
        armTimeout()
        central?.connect(peripheral, options: nil)
    }

    func disconnect() {
        deadline?.cancel()
        password = nil
        guard let peripheral = current, !demo else { clearSession(); return }
        phase = .disconnecting
        central?.cancelPeripheralConnection(peripheral)
        // Keep the active ID until CoreBluetooth confirms cancellation. This prevents
        // callbacks from the old session from being mistaken for a new connection.
    }

    func forgetPassword(_ id: UUID) {
        do { try credentials.delete(id) }
        catch { errorMessage = error.localizedDescription }
    }

    func setPower(_ value: Bool) {
        guard phase == .ready, let id = activeID else { return }
        if demo {
            update(id) { $0.isOn = value; $0.lastConfirmed = Date(); $0.stateSource = .demo }
            return
        }
        phase = .changing
        targetPower = value
        writeQueued = true
        armTimeout()
        sendPowerWhenReady()
    }

    private func sendPowerWhenReady() {
        guard phase == .changing, writeQueued, let target = targetPower,
              let peripheral = current, let characteristic = characteristics[stateID],
              peripheral.canSendWriteWithoutResponse else { return }
        writeQueued = false
        peripheral.writeValue(Data([target ? 1 : 0]), for: characteristic, type: .withoutResponse)
        peripheral.readValue(for: characteristic)
    }

    func rename(_ name: String) {
        guard phase == .ready, let id = activeID else { return }
        do {
            let data = try SwitchProtocol.eightASCII(name)
            if demo { update(id) { $0.name = name }; return }
            guard let characteristic = characteristics[nameID] else { return }
            targetName = name.trimmingCharacters(in: .whitespaces)
            phase = .renaming
            armTimeout()
            current?.writeValue(data, for: characteristic, type: .withResponse)
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() {
        guard phase == .ready else { return }
        if demo { return }
        phase = .refreshing
        readAll()
    }

    func suspend() { stopScan(); disconnect() }

    func setDemo(_ enabled: Bool) {
        guard activeID == nil else { return }
        stopScan()
        demo = enabled
        devices = enabled ? [
            SwitchDevice(id: UUID(), name: "DESKLAMP", rssi: -48, battery: 92, isOn: true, firmware: "v1.0.0", lastConfirmed: Date(), stateSource: .demo),
            SwitchDevice(id: UUID(), name: "CORNER01", rssi: -65, battery: 78, isOn: false, firmware: "v1.0.0", lastConfirmed: Date(), stateSource: .demo),
            SwitchDevice(id: UUID(), name: "SHELFLED", rssi: -57, battery: 86, isOn: true, firmware: "v1.0.0", lastConfirmed: Date(), stateSource: .demo)
        ] : []
        peripherals.removeAll()
        errorMessage = nil
    }

    private func update(_ id: UUID, _ change: (inout SwitchDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        change(&devices[index])
    }

    private func armTimeout() {
        deadline?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.fail("The switch did not respond in time. Move closer, check its password, and make sure the Raspberry Pi has released its connection.")
        }
        deadline = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: task)
    }

    private func fail(_ message: String) {
        errorMessage = message
        disconnect()
    }

    private func clearSession() {
        deadline?.cancel()
        deadline = nil
        password = nil
        current = nil
        activeID = nil
        characteristics.removeAll()
        reads.removeAll()
        targetPower = nil
        targetName = nil
        writeQueued = false
        phase = .idle
    }

    private func ready() {
        deadline?.cancel()
        targetPower = nil
        targetName = nil
        phase = .ready
    }

    private func readAll() {
        reads = [nameID, batteryID, stateID]
        armTimeout()
        for id in reads {
            guard let characteristic = characteristics[id] else {
                fail("A required switch characteristic is missing."); return
            }
            current?.readValue(for: characteristic)
        }
    }
}

extension BluetoothStore: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: radio = "Bluetooth is ready"
        case .poweredOff: radio = "Turn on Bluetooth in Settings to find your switches."
        case .unauthorized: radio = "Allow Bluetooth for Nultra in Settings → Privacy & Security → Bluetooth."
        case .unsupported: radio = "Bluetooth LE is not available on this device. Use a physical iPhone."
        case .resetting: radio = "Bluetooth is restarting. Try scanning again shortly."
        case .unknown: radio = "Waiting for Bluetooth…"
        @unknown default: radio = "Bluetooth is unavailable."
        }
        if central.state == .poweredOn, scanWhenReady { startScan() }
        else if central.state != .poweredOn {
            let waiting = scanWhenReady && central.state == .unknown
            stopScan()
            scanWhenReady = waiting
            clearSession()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning, !demo else { return }
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisedName = localName ?? peripheral.name ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard advertisedName.contains("Nultra") || services.contains(serviceID) else { return }
        peripherals[peripheral.identifier] = peripheral
        if !devices.contains(where: { $0.id == peripheral.identifier }) {
            let label = "Nultra · " + peripheral.identifier.uuidString.prefix(4)
            devices.append(SwitchDevice(id: peripheral.identifier, name: label, rssi: RSSI.intValue))
        }
        update(peripheral.identifier) {
            $0.observe(localName: localName, rssi: RSSI.intValue, at: Date(),
                       acceptsState: activeID != peripheral.identifier)
        }

    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard current === peripheral, phase == .connecting else { return }
        phase = .discovering
        armTimeout()
        peripheral.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard current === peripheral else { return }
        if phase != .disconnecting { errorMessage = error?.localizedDescription ?? "Could not connect. Move closer and retry." }
        clearSession()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard current === peripheral else { return }
        if phase != .disconnecting { errorMessage = error?.localizedDescription ?? "The switch disconnected. Reconnect to control it." }
        clearSession()
    }
}

extension BluetoothStore: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard current === peripheral, phase == .discovering else { return }
        if let error = error { fail(error.localizedDescription); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            fail("This device does not expose the Nultra switch service."); return
        }
        peripheral.discoverCharacteristics([stateID, batteryID, nameID, passwordID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard current === peripheral, phase == .discovering else { return }
        if let error = error { fail(error.localizedDescription); return }
        for characteristic in service.characteristics ?? [] { characteristics[characteristic.uuid] = characteristic }
        let requirements: [(CBUUID, CBCharacteristicProperties)] = [
            (stateID, [.read, .writeWithoutResponse]), (batteryID, [.read]),
            (nameID, [.read, .write]), (passwordID, [.write])
        ]
        guard requirements.allSatisfy({ id, properties in characteristics[id]?.properties.isSuperset(of: properties) == true }),
              let auth = characteristics[passwordID], let password = password else {
            fail("The switch’s Bluetooth characteristics do not match the supported protocol."); return
        }
        phase = .authenticating
        armTimeout()
        peripheral.writeValue(password, for: auth, type: .withResponse)
        self.password = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard current === peripheral, phase != .disconnecting else { return }
        if let error = error { fail("The switch rejected a write: \(error.localizedDescription) Check the saved password."); return }
        if characteristic.uuid == passwordID, phase == .authenticating {
            phase = .loading
            readAll()
        } else if characteristic.uuid == nameID, phase == .renaming {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard current === peripheral, phase != .disconnecting, let id = activeID else { return }
        if let error = error { fail(error.localizedDescription); return }
        guard let data = characteristic.value else { fail("The switch returned no data."); return }
        do {
            switch characteristic.uuid {
            case stateID:
                let value = try SwitchProtocol.power(data)
                update(id) { $0.isOn = value; $0.lastConfirmed = Date(); $0.stateSource = .gatt }
                if phase == .changing {
                    guard value == targetPower else {
                        fail("The requested power state was not confirmed. Check the password and try again."); return
                    }
                    ready()
                }
            case batteryID:
                let value = try SwitchProtocol.batteryPercent(data)
                update(id) { $0.battery = value }
            case nameID:
                let value = try SwitchProtocol.deviceName(data)
                update(id) { $0.name = value.name; $0.firmware = value.firmware }
                if phase == .renaming {
                    guard value.name == targetName else { fail("The switch did not confirm its new name."); return }
                    ready()
                }
            default: return
            }
            if phase == .loading || phase == .refreshing {
                reads.remove(characteristic.uuid)
                if reads.isEmpty { ready() }
            }
        } catch { fail(error.localizedDescription) }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard current === peripheral else { return }
        sendPowerWhenReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard current === peripheral, invalidatedServices.contains(where: { $0.uuid == serviceID }) else { return }
        fail("The switch’s services changed. Reconnect before sending another command.")
    }
}
