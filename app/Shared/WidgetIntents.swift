#if os(iOS)
import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct WidgetLightEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Light")
    static let defaultQuery = WidgetLightQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

@available(iOS 17.0, *)
struct WidgetLightQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetLightEntity] {
        guard !identifiers.isEmpty else { return [] }
        return WidgetSnapshot.load().selected(identifiers, limit: 16).map { WidgetLightEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [WidgetLightEntity] {
        WidgetSnapshot.load().lights.map { WidgetLightEntity(id: $0.id, name: $0.name) }
    }
}

@available(iOS 17.0, *)
struct ChooseWidgetLights: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose lights"
    static let description = IntentDescription("Choose up to 16 saved lights in display order. Small shows four, medium eight, and large sixteen. Leave empty for the first saved lights.")
    @Parameter(title: "Lights") var lights: [WidgetLightEntity]?
}

@available(iOS 17.0, *)
struct WidgetPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Change light power"
    static let description = IntentDescription("Open Nultra and apply this power setting using Bluetooth or your backup server.")
    // Run in the containing app, which owns Bluetooth permission and Keychain credentials.
    static var openAppWhenRun: Bool = true
    @Parameter(title: "Light ID") var lightID: String
    @Parameter(title: "On") var on: Bool
    init() {}
    init(id: UUID, on: Bool) { self.lightID = id.uuidString; self.on = on }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        guard let id = UUID(uuidString: lightID) else { return .result() }
        let store = BluetoothStore.shared
        do { _ = try await store.runShortcut(power: on, ids: [id]) }
        catch { store.errorMessage = error.localizedDescription; throw error }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
        #endif
        return .result()
    }
}
#endif
