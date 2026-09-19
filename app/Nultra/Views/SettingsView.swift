import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bluetooth: BluetoothStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 18) {
                        Image("BrandMark").resizable().frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nultra").font(.title.bold())
                            Text("Your space. At your fingertips.").font(.subheadline).foregroundColor(Theme.muted)
                        }
                    }.padding(.vertical, 10)
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Explore demo mode", isOn: Binding(get: { bluetooth.demo }, set: { bluetooth.setDemo($0) }))
                            .disabled(bluetooth.activeID != nil)
                        Text(bluetooth.activeID != nil ? "Disconnect your current switch to change modes." : "Try the interface with three sample switches. Demo mode never sends Bluetooth commands.")
                            .font(.footnote).foregroundColor(Theme.muted)
                    }.panel()
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Private by design", systemImage: "lock.shield").font(.headline)
                        Text("Switch control goes directly from this iPhone over Bluetooth. No server or account is needed. Passwords are stored on this device in Keychain.")
                            .font(.subheadline).foregroundColor(Theme.muted)
                    }.panel()
                    VStack(alignment: .leading, spacing: 16) {
                        Label("A good connection", systemImage: "dot.radiowaves.left.and.right").font(.headline)
                        Text("Keep your switch nearby and powered on. If it won’t connect, disconnect it from the Raspberry Pi first. Nultra controls one switch at a time and disconnects when it goes into the background.")
                            .font(.subheadline).foregroundColor(Theme.muted)
                    }.panel()
                    Text("VERSION 0.1 · PERSONAL EDITION").font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.5).foregroundColor(Theme.muted).frame(maxWidth: .infinity)
                }.padding(24)
            }.background(Theme.background.ignoresSafeArea())
                .navigationTitle("Settings").navigationBarTitleDisplayModeCompat()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark).tint(Theme.mint)
    }
}
