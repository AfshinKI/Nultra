#if canImport(AppIntents)
import AppIntents
import Foundation

struct TurnAllOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn All Off"
    static let description = IntentDescription("Accept an off request immediately, then try Bluetooth and your enabled backup server in the background. Completion is not confirmed.")
    static var openAppWhenRun: Bool = false
    @MainActor func perform() async throws -> some IntentResult {
        try BluetoothStore.shared.acceptShortcut(power: false)
        return .result()
    }
}

struct TurnAllOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn All On"
    static let description = IntentDescription("Accept an on request immediately, then try Bluetooth and your enabled backup server in the background. Completion is not confirmed.")
    static var openAppWhenRun: Bool = false
    @MainActor func perform() async throws -> some IntentResult {
        try BluetoothStore.shared.acceptShortcut(power: true)
        return .result()
    }
}

struct NultraSwitchEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Switch")
    static let defaultQuery = NultraSwitchQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct NultraSwitchQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [NultraSwitchEntity] {
        let saved = SwitchCatalog().load()
        return identifiers.compactMap { id in
            saved.first { $0.id == id }.map { NultraSwitchEntity(id: $0.id, name: $0.name) }
        }
    }
    func suggestedEntities() async throws -> [NultraSwitchEntity] {
        SwitchCatalog().load().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { NultraSwitchEntity(id: $0.id, name: $0.name) }
    }
}

struct SetSwitchPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Switch Power"
    static let description = IntentDescription("Accept a saved switch request immediately, then try Bluetooth and your enabled backup server. Completion is not confirmed.")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Switch") var target: NultraSwitchEntity
    @Parameter(title: "On", default: false) var on: Bool
    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$target) power to \(\.$on)") }
    @MainActor func perform() async throws -> some IntentResult {
        try BluetoothStore.shared.acceptShortcut(power: on, ids: [target.id])
        return .result()
    }
}

struct NultraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TurnAllOffIntent(), phrases: ["Turn all switches off with \(.applicationName)"],
                    shortTitle: "Turn All Off", systemImageName: "lightbulb")
        AppShortcut(intent: TurnAllOnIntent(), phrases: ["Turn all switches on with \(.applicationName)"],
                    shortTitle: "Turn All On", systemImageName: "lightbulb.fill")
    }
}
#endif
