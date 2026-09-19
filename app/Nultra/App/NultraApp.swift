import SwiftUI

@main
struct NultraApp: App {
    @StateObject private var bluetooth = BluetoothStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(bluetooth)
                .preferredColorScheme(.dark)
                .tint(Theme.mint)
                .onChange(of: scenePhase) { phase in
                    if phase == .background { bluetooth.suspend() }
                }
        }
    }
}
