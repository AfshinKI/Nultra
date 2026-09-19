import SwiftUI
#if os(iOS)
import AppIntents
#endif

@main
@MainActor
struct NultraApp: App {
    @StateObject private var bluetooth: BluetoothStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var ranIntentCheck = false

    init() {
        let store = BluetoothStore.shared
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") { store.setDemo(true) }
        if ProcessInfo.processInfo.arguments.contains("--busy-demo") { store.previewBusyCard() }
        #endif
        _bluetooth = StateObject(wrappedValue: store)
        #if os(iOS)
        NultraShortcuts.updateAppShortcutParameters()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(bluetooth)
                .preferredColorScheme(.dark)
                .tint(Theme.mint)
                .onAppear { bluetooth.resume() }
                .task {
                    #if DEBUG && os(iOS)
                    if !ranIntentCheck && ProcessInfo.processInfo.arguments.contains("--test-shortcut-all-off") {
                        ranIntentCheck = true
                        do { _ = try await TurnAllOffIntent().perform() }
                        catch { bluetooth.errorMessage = error.localizedDescription }
                    }
                    #endif
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .background { bluetooth.suspend() }
                    else if phase == .active { bluetooth.resume() }
                }
        }
    }
}
