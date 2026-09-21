import Foundation

@main struct SceneChecks {
    static func main() throws {
        let a = UUID(), b = UUID()
        let scene = SwitchScene(name: "Evening", members: [a, b, a, UUID()])
        assert(scene.targets(known: [a, b]) == [a, b])
        assert(scene.targets(known: []).isEmpty)
        let suite = "nultra-scene-checks-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = SceneCatalog(defaults: defaults)
        catalog.save([scene]); assert(catalog.load() == [scene])
        let settings = RefreshSettings(defaults: defaults)
        assert(settings.enabled && settings.minutes == 30)
        settings.enabled = false; settings.minutes = 15
        assert(!RefreshSettings(defaults: defaults).enabled && settings.minutes == 15)
        settings.minutes = 1; assert(settings.minutes == 30)
        catalog.save([]); assert(catalog.load().isEmpty)
        print("Passed scene targets, persistence, deletion, and refresh defaults")
    }
}
