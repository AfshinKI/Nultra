import Foundation

struct WidgetLight: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let isOn: Bool?
}

struct WidgetSnapshot: Codable, Equatable {
    let date: Date
    let lights: [WidgetLight]
    static var group: String {
        let original = "group.com.afshinki.nultra"
        // AltStore writes its re-signed App Group IDs into each bundle's Info.plist.
        let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        return groups.first { $0 == original || $0.hasPrefix(original + ".") } ?? original
    }
    static let kind = "NultraLights"
    static let empty = WidgetSnapshot(date: .distantPast, lights: [])

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: "widget.snapshot"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return .empty }
        return value
    }
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(data, forKey: "widget.snapshot")
    }
    func selected(_ ids: [UUID], limit: Int) -> [WidgetLight] {
        if ids.isEmpty { return Array(lights.prefix(limit)) }
        var seen = Set<UUID>()
        return Array(ids.compactMap { id in
            seen.insert(id).inserted ? lights.first { $0.id == id } : nil
        }.prefix(limit))
    }
}
