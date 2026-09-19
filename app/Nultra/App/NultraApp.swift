import SwiftUI

@main
struct NultraApp: App {
    @StateObject private var bluetooth = BluetoothStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = BluetoothStore()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") { store.setDemo(true) }
        #endif
        _bluetooth = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(bluetooth)
                .preferredColorScheme(.dark)
                .tint(Theme.mint)
                .onAppear { bluetooth.resume() }
                .onChange(of: scenePhase) { phase in
                    if phase == .background { bluetooth.suspend() }
                    else if phase == .active { bluetooth.resume() }
                }
        }
    }
}
