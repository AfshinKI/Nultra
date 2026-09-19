import Foundation

struct SwitchRequest {
    let id: UUID
    let operation: SwitchTransaction.Operation
    var automatic = false
    var batch = false
}

/// Slots remain occupied until the transport acknowledges disconnection.
struct SwitchSchedule {
    let limit: Int
    private(set) var pending: [SwitchRequest] = []
    private(set) var active = Set<UUID>()
    var hasWork: Bool { !active.isEmpty || !pending.isEmpty }
    func contains(_ id: UUID) -> Bool { active.contains(id) || pending.contains { $0.id == id } }
    @discardableResult mutating func enqueue(_ item: SwitchRequest) -> Bool {
        guard !contains(item.id) else { return false }
        if item.automatic { pending.append(item) }
        else { pending.insert(item, at: pending.firstIndex(where: \.automatic) ?? pending.endIndex) }
        return true
    }
    mutating func takeNext() -> SwitchRequest? {
        guard active.count < limit, !pending.isEmpty else { return nil }
        let item = pending.removeFirst(); active.insert(item.id); return item
    }
    mutating func finished(_ id: UUID) { active.remove(id) }
    mutating func cancelPending() -> [SwitchRequest] {
        let removed = pending; pending.removeAll(); return removed
    }
}

struct BulkProgress {
    let ids: Set<UUID>
    private(set) var results: [UUID: Bool] = [:]
    var complete: Bool { results.count == ids.count }
    var message: String {
        let successes = results.values.filter { $0 }.count
        return complete ? "\(successes)/\(ids.count) updated · \(ids.count - successes) unsuccessful" : "Updating \(results.count)/\(ids.count)…"
    }
    mutating func finish(_ id: UUID, success: Bool) {
        guard ids.contains(id), results[id] == nil else { return }
        results[id] = success
    }
}

struct SwitchCatalog {
    let defaults: UserDefaults
    private let key = "nultra.known-switches.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> [KnownSwitch] {
        guard let data = defaults.data(forKey: key), let rows = try? JSONDecoder().decode([KnownSwitch].self, from: data) else { return [] }
        var ids = Set<UUID>()
        return rows.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ids.insert($0.id).inserted }
    }
    func save(_ identity: KnownSwitch) {
        guard !identity.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var rows = load().filter { $0.id != identity.id }; rows.append(identity)
        if let data = try? JSONEncoder().encode(rows) { defaults.set(data, forKey: key) }
    }
}
