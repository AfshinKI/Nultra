import Security
import Foundation
import Combine
import CoreBluetooth

/// Main-queue transport for short, serialized transactions. Browsing never connects.
final class BluetoothStore: NSObject, ObservableObject {
    @Published private(set) var devices: [SwitchDevice] = []
    @Published private(set) var scanning = false
    @Published private(set) var radio = "Find your nearby switches"
    @Published private(set) var activeID: UUID?
    @Published private(set) var phase = SwitchTransaction.Stage.finished
    @Published private(set) var pendingIDs = Set<UUID>()
    @Published private(set) var demo = false
    @Published var errorMessage: String?

    private struct Request {
        let id: UUID
        let operation: SwitchTransaction.Operation
        let automatic: Bool
    }
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var current: CBPeripheral?
    private var request: Request?
    private var transaction: SwitchTransaction?
    private var queue: [Request] = []
    private var attemptedIdentification = Set<UUID>()
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var deadline: DispatchWorkItem?
    private var scanWhenReady = false
    private var suspended = false
    private var resumeListening = false
    private var known: [KnownSwitch] = []
    private let catalogKey = "nultra.known-switches.v1"
    func setPassword(_ value: String, for id: UUID) -> Bool {
        let item = MasterPasswordStore(account: id.uuidString)
        do {
            if value.isEmpty { try item.remove() }
            else { _ = try SwitchProtocol.eightASCII(value); try item.save(value) }
            
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    private let serviceID = CBUUID(string: SwitchProtocol.service)
    private let stateID = CBUUID(string: SwitchProtocol.state)
    private let nameID = CBUUID(string: SwitchProtocol.name)
    private let passwordID = CBUUID(string: SwitchProtocol.password)

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: catalogKey),
           let saved = try? JSONDecoder().decode([KnownSwitch].self, from: data) { known = saved }
        restoreKnownDevices()
    }

    func isBusy(_ id: UUID) -> Bool { activeID == id || pendingIDs.contains(id) }

    func startScan() {
        guard !demo else { return }
        suspended = false
        if central == nil {
            scanWhenReady = true
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        guard central?.state == .poweredOn else { errorMessage = radio; return }
        scanWhenReady = false
        attemptedIdentification.removeAll()
        central?.stopScan()
        scanning = true
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        scanWhenReady = false
        central?.stopScan()
        scanning = false
        queue.removeAll { $0.automatic }
        syncPending()
        if request?.automatic == true { process(.cancel) }
    }

    func identify(_ id: UUID) { enqueue(id, .identify, automatic: false) }
    func setPower(_ id: UUID, _ value: Bool) { enqueue(id, .power(value), automatic: false) }
    func rename(_ id: UUID, _ name: String) {
        do {
            _ = try SwitchProtocol.eightASCII(name)
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            enqueue(id, .rename(name), automatic: false)
        } catch { errorMessage = error.localizedDescription }
    }

    func resume() {
        suspended = false
        if resumeListening { resumeListening = false; startScan() }
    }

    func suspend() {
        resumeListening = scanning
        suspended = true
        queue.removeAll()
        syncPending()
        stopScan()
        process(.cancel)
    }

    private func enqueue(_ id: UUID, _ operation: SwitchTransaction.Operation, automatic: Bool) {
        guard !isBusy(id) else { return }
        if demo {
            update(id) {
                switch operation {
                case .identify: break
                case .power(let value): $0.isOn = value; $0.lastConfirmed = Date(); $0.stateSource = .demo
                case .rename(let name): $0.name = name.trimmingCharacters(in: .whitespaces)
                }
            }
            return
        }
        guard !suspended else { return }
        if let central = central, central.state != .poweredOn && central.state != .unknown {
            if !automatic { errorMessage = radio }
            return
        }
        let item = Request(id: id, operation: operation, automatic: automatic)
        if automatic { queue.append(item) } else { queue.insert(item, at: 0) }
        syncPending()
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else { pump() }
    }

    private func pump() {
        guard activeID == nil, !suspended, !demo, central?.state == .poweredOn, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        syncPending()
        let peripheral = peripherals[next.id] ?? central?.retrievePeripherals(withIdentifiers: [next.id]).first
        guard let peripheral = peripheral else {
            update(next.id) { $0.lookupError = "Not nearby. Scan and retry." }
            if !next.automatic { errorMessage = "Scan again to find this switch." }
            pump()
            return
        }
        request = next
        current = peripheral
        activeID = next.id
        transaction = SwitchTransaction(operation: next.operation)
        phase = .connecting
        characteristics.removeAll()
        update(next.id) { $0.lookupError = nil }
        peripheral.delegate = self
        // One absolute deadline: never extend connection time for individual phases.
        let task = DispatchWorkItem { [weak self] in self?.process(.timeout) }
        deadline = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: task)
        central?.connect(peripheral, options: nil)
    }

    private func process(_ event: SwitchTransaction.Event) {
        guard var state = transaction else { return }
        let effect = state.handle(event)
        transaction = state
        phase = state.stage
        if effect == .disconnect {
            deadline?.cancel()
            // Cancel immediately, before persisting results or publishing completion.
            if let peripheral = current { central?.cancelPeripheralConnection(peripheral) }
            if let id = activeID, let result = state.result { apply(result, to: id) }
            if let message = state.failure {
                if let id = activeID, request?.operation == .identify { update(id) { $0.lookupError = message } }
                if request?.automatic != true { errorMessage = message }
            }
        } else if let effect = effect { perform(effect) }
        if state.stage == .finished {
            if let message = state.failure {
                if let id = activeID, request?.operation == .identify { update(id) { $0.lookupError = message } }
                if request?.automatic != true { errorMessage = message }
            }
            clearSession()
            pump()
        }
    }

    private func perform(_ effect: SwitchTransaction.Effect) {
        guard let peripheral = current else { return }
        switch effect {
        case .discover: peripheral.discoverServices([serviceID])
        case .authenticate:
            guard let characteristic = characteristics[passwordID] else { fail("Missing password characteristic."); return }
            guard let value = try? MasterPasswordStore(account: peripheral.identifier.uuidString).load(),
                  let password = try? SwitchProtocol.eightASCII(value) else {
                fail("Enter this switch's password in Menu."); return
            }
            peripheral.writeValue(password, for: characteristic, type: .withResponse)
        case .writePower: sendPowerWhenReady()
        case .writeName(let name):
            guard let characteristic = characteristics[nameID], let data = try? SwitchProtocol.eightASCII(name) else {
                fail("Invalid name or missing name characteristic."); return
            }
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        case .readName: read(nameID)
        case .readPower: read(stateID)
        case .disconnect: break
        }
    }

    private func sendPowerWhenReady() {
        guard transaction?.stage == .waitingToWrite,
              case .power(let value) = transaction?.operation,
              let peripheral = current, peripheral.canSendWriteWithoutResponse,
              let characteristic = characteristics[stateID] else { return }
        peripheral.writeValue(Data([value ? 1 : 0]), for: characteristic, type: .withoutResponse)
        process(.powerSent)
    }

    private func read(_ id: CBUUID) {
        guard let characteristic = characteristics[id] else { fail("A required characteristic is missing."); return }
        current?.readValue(for: characteristic)
    }

    private func fail(_ message: String) { process(.failed(message)) }
    private func syncPending() { pendingIDs = Set(queue.map(\.id)) }
    private func update(_ id: UUID, _ change: (inout SwitchDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        change(&devices[index])
    }
    private func apply(_ result: SwitchTransaction.Result, to id: UUID) {
        switch result {
        case .identity(let name, let firmware):
            update(id) { $0.name = name; $0.firmware = firmware; $0.identityKnown = true; $0.lookupError = nil }
            known.removeAll { $0.id == id }
            known.append(KnownSwitch(id: id, name: name, firmware: firmware))
            if let data = try? JSONEncoder().encode(known) { UserDefaults.standard.set(data, forKey: catalogKey) }
        case .power(let value):
            update(id) { $0.isOn = value; $0.lastConfirmed = Date(); $0.stateSource = .gatt }
        }
    }
    private func clearSession() {
        deadline?.cancel(); deadline = nil
        current = nil; request = nil; transaction = nil; activeID = nil
        characteristics.removeAll()
        phase = .finished
    }
    private func restoreKnownDevices() {
        devices = known.map { SwitchDevice(id: $0.id, name: $0.name, rssi: 127, firmware: $0.firmware, identityKnown: true) }
    }

    func setDemo(_ enabled: Bool) {
        guard activeID == nil else { return }
        queue.removeAll(); syncPending(); stopScan()
        demo = enabled
        if enabled {
            devices = ["DESKLAMP", "CORNER01", "SHELFLED", "BEDROOM1", "KITCHEN1", "HALLWAY1"].enumerated().map { index, name in
                SwitchDevice(id: UUID(), name: name, rssi: -48 - index * 5, battery: 92 - index * 7,
                             isOn: index % 2 == 0, firmware: "v1.0.0", lastConfirmed: Date(), stateSource: .demo, identityKnown: true)
            }
        } else { restoreKnownDevices() }
        peripherals.removeAll(); errorMessage = nil
    }
}

extension BluetoothStore: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: radio = "Bluetooth ready"
        case .poweredOff: radio = "Turn on Bluetooth in Settings."
        case .unauthorized: radio = "Allow Nultra in Settings → Privacy & Security → Bluetooth."
        case .unsupported: radio = "Bluetooth requires a physical iPhone."
        case .resetting: radio = "Bluetooth is restarting."
        case .unknown: radio = "Waiting for Bluetooth…"
        @unknown default: radio = "Bluetooth unavailable."
        }
        if central.state == .poweredOn {
            if scanWhenReady { startScan() }
            pump()
        } else if central.state != .unknown {
            queue.removeAll(); syncPending(); stopScan(); process(.cancel)
            clearSession()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning, !demo else { return }
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard peripherals[peripheral.identifier] != nil || (localName ?? peripheral.name ?? "").contains("Nultra") || services.contains(serviceID) else { return }
        let id = peripheral.identifier
        peripherals[id] = peripheral
        if !devices.contains(where: { $0.id == id }) {
            devices.append(SwitchDevice(id: id, name: "Reading name…", rssi: RSSI.intValue))
        }
        let acceptsState = activeID != id
        update(id) { $0.observe(localName: localName, rssi: RSSI.intValue, at: Date(), acceptsState: acceptsState) }
        if devices.first(where: { $0.id == id })?.identityKnown == false,
           !attemptedIdentification.contains(id) {
            attemptedIdentification.insert(id)
            enqueue(id, .identify, automatic: true)
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard current === peripheral else { return }
        process(.connected)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard current === peripheral else { return }
        if phase != .disconnecting { fail(error?.localizedDescription ?? "Could not connect to the switch.") }
        process(.disconnected)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard current === peripheral else { return }
        if let error = error, phase != .disconnecting { fail(error.localizedDescription) }
        process(.disconnected)
    }
}

extension BluetoothStore: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard current === peripheral, phase == .discovering else { return }
        if let error = error { fail(error.localizedDescription); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceID }), let operation = transaction?.operation else {
            fail("This device does not expose the Nultra service."); return
        }
        let target: CBUUID
        if case .power = operation { target = stateID } else { target = nameID }
        peripheral.discoverCharacteristics([passwordID, target], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard current === peripheral, phase == .discovering else { return }
        if let error = error { fail(error.localizedDescription); return }
        for characteristic in service.characteristics ?? [] { characteristics[characteristic.uuid] = characteristic }
        guard characteristics[passwordID]?.properties.contains(.write) == true, let operation = transaction?.operation else {
            fail("The password characteristic is missing or unsupported."); return
        }
        let target: CBUUID
        let properties: CBCharacteristicProperties
        switch operation {
        case .identify: target = nameID; properties = [.read]
        case .power: target = stateID; properties = [.read, .writeWithoutResponse]
        case .rename: target = nameID; properties = [.read, .write]
        }
        guard characteristics[target]?.properties.isSuperset(of: properties) == true else {
            fail("The switch does not support this operation."); return
        }
        process(.prepared)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard current === peripheral, phase != .disconnecting else { return }
        if let error = error { fail(error.localizedDescription); return }
        if characteristic.uuid == passwordID { process(.authenticated) }
        else if characteristic.uuid == nameID { process(.nameWritten) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard current === peripheral, phase == .reading else { return }
        if let error = error { fail(error.localizedDescription); return }
        guard let data = characteristic.value else { fail("The switch returned no data."); return }
        do {
            if characteristic.uuid == nameID {
                let value = try SwitchProtocol.deviceName(data)
                process(.nameRead(value.name, value.firmware))
            } else if characteristic.uuid == stateID { process(.powerRead(try SwitchProtocol.power(data))) }
        } catch { fail(error.localizedDescription) }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard current === peripheral else { return }
        sendPowerWhenReady()
    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard current === peripheral, invalidatedServices.contains(where: { $0.uuid == serviceID }) else { return }
        fail("The switch’s services changed. Retry the operation.")
    }
}

struct MasterPasswordStore {
    let account: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.afshinki.nultra.master-password",
         kSecAttrAccount as String: account]
    }
    func load() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .ascii) else {
            throw StorageError.failed(status: status)
        }
        // Upgrade existing entries while unlocked; later background shortcuts can read them
        // after the first device unlock following a restart, without cloud/device migration.
        SecItemUpdate(query as CFDictionary, [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary)
        return value
    }
    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let changes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageError.failed(status: status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.failed(status: status) }
    }
    enum StorageError: LocalizedError {
        case failed(status: OSStatus)
        var errorDescription: String? {
            switch self {
            case .failed(let status):
                return "Could not access the saved credential (Keychain \(status)). Unlock your phone and save it again in Menu."
            }
        }
    }
}
