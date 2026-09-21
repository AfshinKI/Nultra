import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor
struct RefreshSettingsView: View {
    @State private var enabled = RefreshSettings().enabled
    @State private var minutes = RefreshSettings().minutes
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Background refresh", systemImage: "arrow.clockwise").font(.headline)
            Toggle("Enable background refresh", isOn: $enabled).accessibilityIdentifier("refresh.enabled")
                .onChange(of: enabled) { RefreshSettings().enabled = $0; schedule() }
            Picker("Requested interval", selection: $minutes) {
                ForEach(RefreshSettings.intervals, id: \.self) { Text("\($0) minutes").tag($0) }
            }.onChange(of: minutes) { RefreshSettings().minutes = $0; schedule() }
            Text("Refreshes battery and widget state through your enabled backup server. The OS chooses when to run; this interval is a minimum request, not a guarantee. Bluetooth discovery resumes when you open Nultra. Force-quitting or system battery restrictions may stop refreshes.")
                .font(.caption).foregroundColor(Theme.muted)
            Text(ServerConfiguration.load().enabled ? "Backup server configured" : "Enable and configure Backup server to receive background readings.")
                .font(.caption).foregroundColor(Theme.muted)
            #if os(iOS)
            if UIApplication.shared.backgroundRefreshStatus != .available {
                Text("Background App Refresh is unavailable. Check iPhone Settings and Low Power Mode.").font(.caption).foregroundColor(.orange)
            }
            #endif
            if let date = UserDefaults.standard.object(forKey: "refresh.lastSuccess") as? Date {
                Text("Last background refresh: \(date.formatted())").font(.caption).foregroundColor(Theme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
    private func schedule() {
        #if os(iOS)
        BackgroundRefresh.shared.schedule()
        #endif
    }
}
