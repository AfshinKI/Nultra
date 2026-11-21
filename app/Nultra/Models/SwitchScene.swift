import Foundation

struct SwitchScene: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var members: [UUID]
    func targets(known: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return members.filter { known.contains($0) && seen.insert($0).inserted }
    }
}

struct SceneCatalog {
    var defaults = UserDefaults.standard
    private let key = "nultra.scenes.v1"
    func load() -> [SwitchScene] {
        guard let data = defaults.data(forKey: key), let scenes = try? JSONDecoder().decode([SwitchScene].self, from: data) else { return [] }
        var seen = Set<UUID>()
        return scenes.filter { seen.insert($0.id).inserted }
    }
    func save(_ scenes: [SwitchScene]) {
        guard let data = try? JSONEncoder().encode(scenes) else { return }
        defaults.set(data, forKey: key)
    }
}
