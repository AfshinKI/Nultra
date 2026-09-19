import Foundation
import Combine
import CoreBluetooth

/// Main-queue adapter: at most three independent short transactions, no idle connections.
final class BluetoothStore: NSObject, ObservableObject {
    @Published private(set) var devices: [SwitchDevice] = []
    @Published private(set) var scanning = false
    @Published private(set) var radio = "Starting Bluetooth…"
    @Published private(set) var phases: [UUID: SwitchTransaction.Stage] = [:]
    @Published private(set) var pendingIDs = Set<UUID>()
    @Published private(set) var demo = false
    @Published private(set) var now = Date()
    @Published private(set) var bulkStatus: String?
    @Published var errorMessage: String?

    private final class Session {
        let peripheral: CBPeripheral
        let request: SwitchRequest
        let password: Data
        var transaction: SwitchTransaction
        var characteristics: [CBUUID: CBCharacteristic] = [:]
        var deadline: DispatchWorkItem?
        init(_ peripheral: CBPeripheral, _ request: SwitchRequest, password: Data) {
            self.peripheral = peripheral; self.request = request; self.password = password
            transaction = SwitchTransaction(operation: request.operation)
        }
    }
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var sessions: [UUID: Session] = [:]
    private var schedule = SwitchSchedule(limit: 3)
    private var bulk: BulkProgress?
    private var attemptedIdentification = Set<UUID>()
    private var suspended = true
    private var presenceTimer: Timer?
    private let catalog = SwitchCatalog()
    func setPassword(_ value: String, for id: UUID) -> Bool {
        let item = MasterPasswordStore(account: id.uuidString)
        do {
            if value.isEmpty { try item.remove() }
            else { _ = try SwitchProtocol.eightASCII(value); try item.save(value) }
            retryDiscovery()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    private let serviceID = CBUUID(string: SwitchProtocol.service)
    private let stateID = CBUUID(string: SwitchProtocol.state)
    private let nameID = CBUUID(string: SwitchProtocol.name)
    private let passwordID = CBUUID(string: SwitchProtocol.password)

    var visibleDevices: [SwitchDevice] { devices.filter(\.visible).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var hasWork: Bool { !phases.isEmpty || !pendingIDs.isEmpty }

    var unnamedCount: Int { devices.filter { !$0.visible }.count }
    func isBusy(_ id: UUID) -> Bool { phases[id] != nil || pendingIDs.contains(id) }
    func status(_ id: UUID) -> String { phases[id]?.label ?? (pendingIDs.contains(id) ? "Queued…" : "Disconnected") }
    func online(_ device: SwitchDevice) -> Bool {
        if demo { return device.lastSeen != nil }
        return scanning && device.isOnline(at: now)
    }

    override init() {
        super.init()
        restoreKnownDevices()
    }




    func resume() {
        if suspended { attemptedIdentification.removeAll() }
        suspended = false
        now = Date()
        if presenceTimer == nil {
            presenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.now = Date() }
        }
        startScan()
    }
    private func startScan() {
        guard !demo, !suspended else { return }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main); return }
        guard central?.state == .poweredOn, !scanning else { return }
        scanning = true
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    private func stopScan() { central?.stopScan(); scanning = false }
    func suspend() {
        suspended = true
        presenceTimer?.invalidate(); presenceTimer = nil
        stopScan()
        for request in schedule.cancelPending() { finishBatch(request, success: false) }
        syncWork()
        for id in Array(sessions.keys) { process(id, .cancel) }
    }
    func retryDiscovery() {
        attemptedIdentification.removeAll()
        guard !demo, !suspended else { return }
        for device in devices where !device.visible && peripherals[device.id] != nil && !isBusy(device.id) {
            attemptedIdentification.insert(device.id)
            enqueue(SwitchRequest(id: device.id, operation: .identify, automatic: true))
        }
    }
    func identify(_ id: UUID) { enqueue(SwitchRequest(id: id, operation: .identify)) }
    func setPower(_ id: UUID, _ value: Bool) { enqueue(SwitchRequest(id: id, operation: .power(value))) }
    func rename(_ id: UUID, _ name: String) {
        do {
            _ = try SwitchProtocol.eightASCII(name)
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            enqueue(SwitchRequest(id: id, operation: .rename(name)))
        } catch { errorMessage = error.localizedDescription }
    }
    func setAllPower(_ value: Bool) {
        guard !hasWork, !visibleDevices.isEmpty else { return }
        let targets = visibleDevices.map(\.id)
        bulk = BulkProgress(ids: Set(targets)); bulkStatus = bulk?.message
        if demo {
            for id in targets { setPower(id, value); finishBatch(SwitchRequest(id: id, operation: .power(value), batch: true), success: true) }
            return
        }
        guard !suspended, central?.state == .poweredOn else { bulk = nil; bulkStatus = nil; errorMessage = radio; return }
        for id in targets { schedule.enqueue(SwitchRequest(id: id, operation: .power(value), batch: true)) }
        syncWork(); pump()
    }
    private func enqueue(_ request: SwitchRequest) {
        guard !isBusy(request.id) else { return }
        if demo {
            update(request.id) {
                switch request.operation {
                case .identify: break
                case .power(let value): $0.isOn = value; $0.lastConfirmed = Date(); $0.stateSource = .demo
                case .rename(let name): $0.name = name.trimmingCharacters(in: .whitespaces)
                }
            }
            return
        }
        guard !suspended, central?.state == .poweredOn else {
            if !request.automatic { errorMessage = radio }; return
        }
        schedule.enqueue(request); syncWork(); pump()
    }
    private func pump() {
        guard !suspended, !demo, central?.state == .poweredOn else { return }
        while let next = schedule.takeNext() {
            let peripheral = peripherals[next.id] ?? central?.retrievePeripherals(withIdentifiers: [next.id]).first
            guard let peripheral = peripheral, let value = try? MasterPasswordStore(account: next.id.uuidString).load(), let password = try? SwitchProtocol.eightASCII(value) else {
                schedule.finished(next.id)
                finishBatch(next, success: false)
                if !next.automatic && !next.batch { errorMessage = "Switch unavailable or master password needs saving in Menu." }
                continue
            }
            let session = Session(peripheral, next, password: password)
            sessions[next.id] = session
            peripheral.delegate = self
            update(next.id) { $0.lookupError = nil }
            let task = DispatchWorkItem { [weak self, weak session] in
                guard let self = self, let session = session, self.sessions[next.id] === session else { return }
                self.process(next.id, .timeout)
            }
            session.deadline = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: task)
            central?.connect(peripheral, options: nil)
        }
        syncWork()
    }
    private func process(_ id: UUID, _ event: SwitchTransaction.Event) {
        guard let session = sessions[id] else { return }
        let effect = session.transaction.handle(event)
        if effect == .disconnect {
            session.deadline?.cancel()
            // Cancel before publishing or saving results; never hold a completed link.
            central?.cancelPeripheralConnection(session.peripheral)
            if let result = session.transaction.result { apply(result, to: id) }
        } else if let effect = effect { perform(effect, session) }
        if session.transaction.stage == .finished {
            if let message = session.transaction.failure {
                update(id) { $0.lookupError = message }
                if !session.request.automatic && !session.request.batch { errorMessage = message }
            }
            finishBatch(session.request, success: session.transaction.result != nil && session.transaction.failure == nil)
            // A password edited during this attempt takes effect on the next attempt.
            if session.request.operation == .identify, session.transaction.result == nil,
               let current = try? MasterPasswordStore(account: id.uuidString).load(),
               session.password != Data(current.utf8) { attemptedIdentification.remove(id) }
            session.deadline?.cancel()
            sessions.removeValue(forKey: id); schedule.finished(id)
            pump()
        }
        syncWork()
    }
    private func finishBatch(_ request: SwitchRequest, success: Bool) {
        guard request.batch else { return }
        bulk?.finish(request.id, success: success); bulkStatus = bulk?.message
    }
    private func syncWork() {
        phases = sessions.mapValues { $0.transaction.stage }
        pendingIDs = Set(schedule.pending.map(\.id))
    }
    private func perform(_ effect: SwitchTransaction.Effect, _ session: Session) {
        let peripheral = session.peripheral
        let id = peripheral.identifier
        switch effect {
        case .discover: peripheral.discoverServices([serviceID])
        case .authenticate:
            guard let c = session.characteristics[passwordID] else { fail(id, "Missing password characteristic."); return }
            peripheral.writeValue(session.password, for: c, type: .withResponse)
        case .writePower: sendPowerWhenReady(session)
        case .writeName(let name):
            guard let c = session.characteristics[nameID], let data = try? SwitchProtocol.eightASCII(name) else { fail(id, "Invalid name characteristic."); return }
            peripheral.writeValue(data, for: c, type: .withResponse)
        case .readName: read(nameID, session)
        case .readPower: read(stateID, session)
        case .disconnect: break
        }
    }
    private func sendPowerWhenReady(_ session: Session) {
        guard session.transaction.stage == .waitingToWrite, case .power(let value) = session.transaction.operation,
              session.peripheral.canSendWriteWithoutResponse, let c = session.characteristics[stateID] else { return }
        session.peripheral.writeValue(Data([value ? 1 : 0]), for: c, type: .withoutResponse)
        process(session.peripheral.identifier, .powerSent)
    }
    private func read(_ id: CBUUID, _ session: Session) {
        guard let c = session.characteristics[id] else { fail(session.peripheral.identifier, "Missing characteristic."); return }
        session.peripheral.readValue(for: c)
    }
    private func fail(_ id: UUID, _ message: String) { process(id, .failed(message)) }
    private func update(_ id: UUID, _ change: (inout SwitchDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }; change(&devices[index])
    }
    private func apply(_ result: SwitchTransaction.Result, to id: UUID) {
        switch result {
        case .identity(let name, let firmware):
            update(id) { $0.name = name; $0.firmware = firmware; $0.identityKnown = true; $0.lookupError = nil }
            catalog.save(KnownSwitch(id: id, name: name, firmware: firmware))
        case .power(let value): update(id) { $0.isOn = value; $0.lastConfirmed = Date(); $0.stateSource = .gatt }
        }
    }
    private func restoreKnownDevices() {
        devices = catalog.load().map { SwitchDevice(id: $0.id, name: $0.name, rssi: 127, firmware: $0.firmware, identityKnown: true) }
    }
    func setDemo(_ enabled: Bool) {
        guard !hasWork else { return }
        stopScan(); demo = enabled; bulk = nil; bulkStatus = nil
        if enabled {
            devices = ["DESKLAMP", "CORNER01", "SHELFLED", "BEDROOM1", "KITCHEN1", "HALLWAY1"].enumerated().map { index, name in
                SwitchDevice(id: UUID(), name: name, rssi: -48 - index * 5, battery: 92 - index * 7,
                             isOn: index % 2 == 0, firmware: "v1.0.0", lastConfirmed: Date(),
                             lastSeen: index == 5 ? nil : Date(), stateSource: .demo, identityKnown: true)
            }
            // A hidden unnamed candidate verifies that the public grid only shows real names.
            devices.append(SwitchDevice(id: UUID(), name: "UNNAMED", rssi: -55))
        } else { restoreKnownDevices() }
        peripherals.removeAll(); attemptedIdentification.removeAll()
        startScan()
    }
}

extension BluetoothStore: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: radio = "Listening for switches"
        case .poweredOff: radio = "Turn on Bluetooth in Settings."
        case .unauthorized: radio = "Allow Nultra in Settings → Privacy & Security → Bluetooth."
        case .unsupported: radio = "Bluetooth requires a physical iPhone."
        case .resetting: radio = "Bluetooth is restarting."
        case .unknown: radio = "Starting Bluetooth…"
        @unknown default: radio = "Bluetooth unavailable."
        }
        if central.state == .poweredOn { startScan(); pump() }
        else if central.state != .unknown {
            stopScan()
            for request in schedule.cancelPending() { finishBatch(request, success: false) }
            for id in Array(sessions.keys) { process(id, .cancel); process(id, .disconnected) }
            syncWork()
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning, !demo else { return }
        let id = peripheral.identifier
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard devices.contains(where: { $0.id == id }) || (localName ?? peripheral.name ?? "").contains("Nultra") || services.contains(serviceID) else { return }
        peripherals[id] = peripheral
        if !devices.contains(where: { $0.id == id }) { devices.append(SwitchDevice(id: id, name: "", rssi: RSSI.intValue)) }
        let acceptsState = sessions[id] == nil
        let observed = Date(); now = observed
        update(id) { $0.observe(localName: localName, rssi: RSSI.intValue, at: observed, acceptsState: acceptsState) }
        if devices.first(where: { $0.id == id })?.visible == false, !attemptedIdentification.contains(id) {
            attemptedIdentification.insert(id)
            enqueue(SwitchRequest(id: id, operation: .identify, automatic: true))
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard sessions[peripheral.identifier]?.peripheral === peripheral else { return }; process(peripheral.identifier, .connected)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let session = sessions[peripheral.identifier], session.peripheral === peripheral else { return }
        if session.transaction.stage != .disconnecting { fail(peripheral.identifier, error?.localizedDescription ?? "Could not connect.") }
        process(peripheral.identifier, .disconnected)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let session = sessions[peripheral.identifier], session.peripheral === peripheral else { return }
        if let error = error, session.transaction.stage != .disconnecting { fail(peripheral.identifier, error.localizedDescription) }
        process(peripheral.identifier, .disconnected)
    }
}

extension BluetoothStore: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let id = peripheral.identifier
        guard let s = sessions[id], s.peripheral === peripheral, s.transaction.stage == .discovering else { return }
        if let error = error { fail(id, error.localizedDescription); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else { fail(id, "Nultra service missing."); return }
        let target: CBUUID
        if case .power = s.transaction.operation { target = stateID } else { target = nameID }
        peripheral.discoverCharacteristics([passwordID, target], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let id = peripheral.identifier
        guard let s = sessions[id], s.peripheral === peripheral, s.transaction.stage == .discovering else { return }
        if let error = error { fail(id, error.localizedDescription); return }
        for c in service.characteristics ?? [] { s.characteristics[c.uuid] = c }
        guard s.characteristics[passwordID]?.properties.contains(.write) == true else { fail(id, "Password characteristic unsupported."); return }
        let target: CBUUID; let properties: CBCharacteristicProperties
        switch s.transaction.operation {
        case .identify: target = nameID; properties = [.read]
        case .power: target = stateID; properties = [.read, .writeWithoutResponse]
        case .rename: target = nameID; properties = [.read, .write]
        }
        guard s.characteristics[target]?.properties.isSuperset(of: properties) == true else { fail(id, "Operation not supported by switch."); return }
        process(id, .prepared)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = peripheral.identifier
        guard let s = sessions[id], s.peripheral === peripheral, s.transaction.stage != .disconnecting else { return }
        if let error = error { fail(id, error.localizedDescription); return }
        if characteristic.uuid == passwordID { process(id, .authenticated) }
        else if characteristic.uuid == nameID { process(id, .nameWritten) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = peripheral.identifier
        guard let s = sessions[id], s.peripheral === peripheral, s.transaction.stage == .reading else { return }
        if let error = error { fail(id, error.localizedDescription); return }
        guard let data = characteristic.value else { fail(id, "Switch returned no data."); return }
        do {
            if characteristic.uuid == nameID { let value = try SwitchProtocol.deviceName(data); process(id, .nameRead(value.name, value.firmware)) }
            else if characteristic.uuid == stateID { process(id, .powerRead(try SwitchProtocol.power(data))) }
        } catch { fail(id, error.localizedDescription) }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard let s = sessions[peripheral.identifier], s.peripheral === peripheral else { return }; sendPowerWhenReady(s)
    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard sessions[peripheral.identifier]?.peripheral === peripheral, invalidatedServices.contains(where: { $0.uuid == serviceID }) else { return }
        fail(peripheral.identifier, "Switch service changed. Retry the operation.")
    }
}
