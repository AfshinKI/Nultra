import Foundation
import Combine
import CoreBluetooth
#if os(iOS)
import UIKit
#endif

/// Main-queue adapter: at most three independent short transactions, no idle connections.
final class BluetoothStore: NSObject, ObservableObject {
    @MainActor static let shared = BluetoothStore()
    private var liveDevices: [SwitchDevice] = []
    @Published private(set) var devices: [SwitchDevice] = []
    @Published private(set) var scanning = false
    @Published private(set) var radio = "Starting Bluetooth…"
    @Published private(set) var phases: [UUID: SwitchTransaction.Stage] = [:]
    @Published private(set) var pendingIDs = Set<UUID>()
    @Published private(set) var demo = false
    @Published private(set) var now = Date()
    @Published private(set) var bulkStatus: String?
    @Published private(set) var shortcutRunning = false
    @Published var errorMessage: String?

    @Published private(set) var serverConfiguration = ServerConfiguration.load()
    @Published private(set) var serverDevices: [ServerSwitch] = []
    @Published private(set) var serverStatus = "Not checked"
    @Published private(set) var checkingServer = false
    private var serverCheckedAt: Date?
    private var serverPoll: Task<Void, Never>?
    private var remoteTasks: [UUID: Task<Void, Never>] = [:]
    private var remoteQueued = Set<UUID>()
    private var shortcutExpired = false
    private var canOperate: Bool { !suspended || shortcutRunning }

    func saveServer(_ value: ServerConfiguration) {
        guard !hasWork else { return }
        do {
            if value.enabled || !value.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { _ = try value.baseURL() }
            var value = value
            value.address = value.address.trimmingCharacters(in: .whitespacesAndNewlines)
            value.mappings = value.address == serverConfiguration.address ? serverConfiguration.mappings : [:]
            serverConfiguration = value; value.save()
            serverDevices = []; serverCheckedAt = nil; serverStatus = "Not checked"
            serverPoll?.cancel(); serverPoll = nil
            if !suspended { startServerPolling() }
        } catch { errorMessage = error.localizedDescription }
    }
    func mapServer(_ id: UUID, address: String) {
        guard !hasWork else { return }
        serverConfiguration.mappings[id.uuidString] = address.isEmpty ? nil : address
        serverConfiguration.save()
    }
    @MainActor func checkServer() async {
        guard !demo, !suspended, serverConfiguration.enabled, !checkingServer else { return }
        checkingServer = true
        let configuration = serverConfiguration
        defer { checkingServer = false }
        do {
            let client = try ServerClient(configuration: configuration)
            defer { client.close() }
            let rows = try await client.devices()
            try Task.checkCancellation()
            guard configuration == serverConfiguration else { return }
            serverDevices = rows; serverCheckedAt = Date()
            serverStatus = "Reachable · \(rows.filter(\.available).count) switches recently seen"
            for device in catalog.load() where sessions[device.id] == nil && !liveDevices.contains(where: { $0.id == device.id && $0.isOnline(at: Date()) }) {
                guard let row = try? ServerMapping.resolve(device, known: catalog.load(), rows: rows, configuration: configuration) else { continue }
                update(device.id) {
                    $0.isOn = row.switch_state.flatMap { [0, 1].contains($0) ? $0 == 1 : nil }
                    $0.battery = row.battery.flatMap { (0...100).contains($0) ? $0 : nil }
                    $0.stateSource = .server
                }
            }
        } catch {
            guard configuration == serverConfiguration else { return }
            serverCheckedAt = nil; serverStatus = "Unavailable: \(error.localizedDescription)"
        }
    }
    private func startServerPolling() {
        guard !demo, !suspended, serverConfiguration.enabled, serverPoll == nil else { return }
        serverPoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self, !self.suspended else { return }
                await self.checkServer()
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            }
        }
    }
    func serverOnline(_ device: SwitchDevice) -> Bool {
        guard !demo, serverConfiguration.enabled, let date = serverCheckedAt, Date().timeIntervalSince(date) < 30,
              let known = catalog.load().first(where: { $0.id == device.id }) else { return false }
        return (try? ServerMapping.resolve(known, known: catalog.load(), rows: serverDevices, configuration: serverConfiguration)) != nil
    }
    private func startRemote(_ request: SwitchRequest) {
        guard case .power(let on) = request.operation else { return }
        let configuration = serverConfiguration
        remoteTasks[request.id] = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var accepted = false
            defer {
                self.remoteTasks.removeValue(forKey: request.id)
                self.schedule.finished(request.id)
                self.finishBatch(request, success: accepted)
                self.syncWork(); self.pump()
            }
            do {
                let known = self.catalog.load()
                guard let device = known.first(where: { $0.id == request.id }) else { throw SwitchAction.Failure.unknownSwitch }
                let client = try ServerClient(configuration: configuration)
                defer { client.close() }
                let rows = try await client.devices()
                try Task.checkCancellation()
                let row = try ServerMapping.resolve(device, known: known, rows: rows, configuration: configuration)
                // Pin the first unambiguous mapping so later renames cannot redirect a command.
                self.serverConfiguration.mappings[device.id.uuidString] = row.address
                self.serverConfiguration.save()
                try await client.setPower(address: row.address, on: on)
                try Task.checkCancellation()
                accepted = true
                self.remoteQueued.insert(request.id)
                self.update(request.id) { $0.lookupError = nil }
                self.serverStatus = "Command queued for \(device.name); waiting for server state"
                // Do not invent an observed state or mark this as Bluetooth confirmation.
            } catch {
                if !Task.isCancelled {
                    self.update(request.id) { $0.lookupError = error.localizedDescription }
                    if !request.batch { self.errorMessage = error.localizedDescription }
                }
            }
        }
        syncWork()
    }

    private final class Session {
        let peripheral: CBPeripheral
        let request: SwitchRequest
        let password: Data
        var transaction: SwitchTransaction
        var characteristics: [CBUUID: CBCharacteristic] = [:]
        var deadline: DispatchWorkItem?
        var cancelled = false
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
    var hasWork: Bool { shortcutRunning || !phases.isEmpty || !pendingIDs.isEmpty || !remoteTasks.isEmpty }

    var unnamedCount: Int { devices.filter { !$0.visible }.count }
    func isBusy(_ id: UUID) -> Bool { shortcutRunning || phases[id] != nil || pendingIDs.contains(id) }
    func status(_ id: UUID) -> String { phases[id]?.label ?? (pendingIDs.contains(id) ? "Queued…" : "Disconnected") }
    func online(_ device: SwitchDevice) -> Bool {
        if demo { return device.lastSeen != nil }
        return (scanning && device.isOnline(at: now)) || serverOnline(device)
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
            presenceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.publishDevices() }
        }
        startScan()
        startServerPolling()
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
        serverPoll?.cancel(); serverPoll = nil
        if !shortcutRunning { cancelOperations() }
    }
    private func cancelOperations() {
        for task in remoteTasks.values { task.cancel() }
        for request in schedule.cancelPending() { finishBatch(request, success: false) }
        for id in Array(sessions.keys) { sessions[id]?.cancelled = true; process(id, .cancel) }
        syncWork()
    }
    func retryDiscovery() {
        attemptedIdentification.removeAll()
        guard !demo, !suspended, !shortcutRunning else { return }
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
        startBulk(targets: visibleDevices.map(\.id), power: value)
    }
    private func startBulk(targets: [UUID], power value: Bool) {
        remoteQueued.removeAll()
        bulk = BulkProgress(ids: Set(targets)); bulkStatus = bulk?.message
        if demo {
            for id in targets { setPower(id, value); finishBatch(SwitchRequest(id: id, operation: .power(value), batch: true), success: true) }
            return
        }
        guard canOperate, central?.state == .poweredOn || serverConfiguration.enabled else { bulk = nil; bulkStatus = nil; errorMessage = radio; return }
        for id in targets { schedule.enqueue(SwitchRequest(id: id, operation: .power(value), batch: true)) }
        syncWork(); pump()
    }
    /// Runs in the intent's background execution window; never opens the scene or starts discovery.
    @MainActor func runShortcut(power: Bool, ids: [UUID]? = nil) async throws -> String {
        guard !demo else { throw SwitchAction.Failure.demo }
        guard !hasWork else { throw SwitchAction.Failure.busy }
        let targets = try SwitchAction.targets(requested: ids, known: catalog.load())
        shortcutRunning = true; shortcutExpired = false
        #if os(iOS)
        let background = UIApplication.shared.beginBackgroundTask(withName: "Nultra shortcut") { [weak self] in
            self?.shortcutExpired = true; self?.cancelOperations()
        }
        #endif
        defer {
            shortcutRunning = false
            if suspended { stopScan() }
            #if os(iOS)
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            #endif
        }
        do {
            if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
            let radioDeadline = Date().addingTimeInterval(3)
            while central?.state == .unknown || central?.state == .resetting {
                guard !shortcutExpired else { throw SwitchAction.Failure.interrupted }
                if Date() >= radioDeadline { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard central?.state == .poweredOn || serverConfiguration.enabled else { throw SwitchAction.Failure.bluetooth(radio) }
            try Task.checkCancellation()
            startBulk(targets: targets, power: power)
            let deadline = Date().addingTimeInterval(24)
            while bulk?.complete != true {
                guard !shortcutExpired, Date() < deadline else { throw SwitchAction.Failure.interrupted }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try Task.checkCancellation()
            let successes = bulk?.results.values.filter { $0 }.count ?? 0
            guard successes == targets.count else { throw SwitchAction.Failure.partial(successes, targets.count) }
            let queued = remoteQueued.count
            if queued > 0 { return "Bluetooth confirmed \(successes - queued); sent \(queued) to the backup server. Server completion is not confirmed." }
            return "Turned \(power ? "on" : "off") \(successes) switch\(successes == 1 ? "" : "es")."
        } catch {
            cancelOperations()
            throw error
        }
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
        guard canOperate, central?.state == .poweredOn || (serverConfiguration.enabled && request.operation.isPower) else {
            if !request.automatic { errorMessage = radio }; return
        }
        schedule.enqueue(request); syncWork(); pump()
    }
    private func pump() {
        guard canOperate, !demo else { return }
        while let next = schedule.takeNext() {
            let nearby = liveDevices.first(where: { $0.id == next.id })?.isOnline(at: Date()) == true
            if serverConfiguration.enabled, next.operation.isPower, (!nearby && !shortcutRunning) || central?.state != .poweredOn {
                startRemote(next); continue
            }
            let peripheral = peripherals[next.id] ?? central?.retrievePeripherals(withIdentifiers: [next.id]).first
            guard central?.state == .poweredOn, let peripheral = peripheral, let value = try? MasterPasswordStore(account: next.id.uuidString).load(), let password = try? SwitchProtocol.eightASCII(value) else {
                if serverConfiguration.enabled && next.operation.isPower { startRemote(next); continue }
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
                if !session.request.automatic && !session.request.batch && !(session.request.operation.isPower && serverConfiguration.enabled) { errorMessage = message }
            }
            let succeeded = session.transaction.result != nil && session.transaction.failure == nil
            let fallback = !succeeded && !session.cancelled && canOperate && (!shortcutRunning || !shortcutExpired) && session.request.operation.isPower && serverConfiguration.enabled
            if !fallback { finishBatch(session.request, success: succeeded) }
            // A password edited during this attempt takes effect on the next attempt.
            if session.request.operation == .identify, session.transaction.result == nil,
               let current = try? MasterPasswordStore(account: id.uuidString).load(),
               session.password != Data(current.utf8) { attemptedIdentification.remove(id) }
            session.deadline?.cancel()
            sessions.removeValue(forKey: id)
            if fallback { startRemote(session.request) } else { schedule.finished(id) }
            pump()
        }
        syncWork()
    }
    private func finishBatch(_ request: SwitchRequest, success: Bool) {
        guard request.batch else { return }
        bulk?.finish(request.id, success: success); bulkStatus = bulk?.message
        if !remoteQueued.isEmpty { bulkStatus = "\(bulk?.results.count ?? 0)/\(bulk?.ids.count ?? 0) handled · \(remoteQueued.count) server-queued, not confirmed" }
    }
    private func syncWork() {
        phases = sessions.mapValues { $0.transaction.stage }
        for id in remoteTasks.keys { phases[id] = .reading }
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
    private func update(_ id: UUID, publish: Bool = true, _ change: (inout SwitchDevice) -> Void) {
        guard let index = liveDevices.firstIndex(where: { $0.id == id }) else { return }
        change(&liveDevices[index])
        if publish { publishDevices() }
    }
    private func publishDevices() {
        now = Date()
        if devices != liveDevices { devices = liveDevices }
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
        liveDevices = catalog.load().map { SwitchDevice(id: $0.id, name: $0.name, rssi: 127, firmware: $0.firmware, identityKnown: true) }
        publishDevices()
    }
    #if DEBUG
    func previewBusyCard() {
        guard demo, let device = devices.first(where: { $0.name == "DESKLAMP" }) else { return }
        phases[device.id] = .authenticating
    }
    #endif
    func setDemo(_ enabled: Bool) {
        guard !hasWork else { return }
        stopScan(); serverPoll?.cancel(); serverPoll = nil; demo = enabled; bulk = nil; bulkStatus = nil
        if enabled {
            liveDevices = ["DESKLAMP", "CORNER01", "SHELFLED", "BEDROOM1", "KITCHEN1", "HALLWAY1"].enumerated().map { index, name in
                SwitchDevice(id: UUID(), name: name, rssi: -48 - index * 5, battery: index == 5 ? 7 : 92 - index * 7,
                             isOn: index % 2 == 0, firmware: "v1.0.0", lastConfirmed: Date(),
                             lastSeen: index == 5 ? nil : Date(), stateSource: .demo, identityKnown: true)
            }
            // A hidden unnamed candidate verifies that the public grid only shows real names.
            liveDevices.append(SwitchDevice(id: UUID(), name: "UNNAMED", rssi: -55))
        } else { restoreKnownDevices() }
        publishDevices()
        peripherals.removeAll(); attemptedIdentification.removeAll()
        startScan()
        startServerPolling()
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
            if !serverConfiguration.enabled {
                for request in schedule.cancelPending() { finishBatch(request, success: false) }
            }
            for id in Array(sessions.keys) { process(id, .failed(radio)); process(id, .disconnected) }
            pump(); syncWork()
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning, !demo else { return }
        let id = peripheral.identifier
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard liveDevices.contains(where: { $0.id == id }) || (localName ?? peripheral.name ?? "").contains("Nultra") || services.contains(serviceID) else { return }
        peripherals[id] = peripheral
        if !liveDevices.contains(where: { $0.id == id }) { liveDevices.append(SwitchDevice(id: id, name: "", rssi: RSSI.intValue)) }
        let acceptsState = sessions[id] == nil
        let observed = Date()
        update(id, publish: false) { $0.observe(localName: localName, rssi: RSSI.intValue, at: observed, acceptsState: acceptsState) }
        if !shortcutRunning, liveDevices.first(where: { $0.id == id })?.visible == false, !attemptedIdentification.contains(id) {
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
