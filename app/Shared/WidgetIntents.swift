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
    static let description = IntentDescription("Choose up to 16 lights, All On, All Off, or scenes in display order. Small shows four, medium eight, and large sixteen. Leave empty for the first saved lights.")
    @Parameter(title: "Lights") var lights: [WidgetLightEntity]?
}

@available(iOS 17.0, *)
struct WidgetPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Change light power"
    static let description = IntentDescription("Apply this power setting in the background using Bluetooth or your backup server.")
    // Run in the containing app, which owns Bluetooth permission and Keychain credentials.
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Light ID") var lightID: String
    @Parameter(title: "On") var on: Bool
    init() {}
    init(id: UUID, on: Bool) { self.lightID = id.uuidString; self.on = on }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        guard let id = UUID(uuidString: lightID) else { throw SwitchAction.Failure.unknownSwitch }
        let store = BluetoothStore.shared
        WidgetSnapshot.recordCommand("Updating…")
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
        do {
            let targets: [UUID]?
            if id == WidgetLight.allOnID || id == WidgetLight.allOffID { targets = nil }
            else if let scene = SceneCatalog().load().first(where: { $0.id == id }) { targets = scene.members }
            else { targets = [id] }
            let result = try await store.runShortcut(power: id == WidgetLight.allOnID ? true : id == WidgetLight.allOffID ? false : on, ids: targets)
            WidgetSnapshot.recordCommand(result)
        }
        catch {
            store.errorMessage = error.localizedDescription
            WidgetSnapshot.recordCommand(error.localizedDescription)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
            throw error
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
        #else
        throw WidgetExecutionFailure.appUnavailable
        #endif
        return .result()
    }
}
private enum WidgetExecutionFailure: LocalizedError {
    case appUnavailable
    var errorDescription: String? { "Nultra could not start the background action. Open Nultra once, then try again." }
}
#if !WIDGET_EXTENSION
@available(iOS 17.0, *)
extension WidgetPowerIntent: ForegroundContinuableIntent {}
#endif
#endif
