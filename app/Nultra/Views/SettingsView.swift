import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bluetooth: BluetoothStore
    @Environment(\.dismiss) private var dismiss

    @State private var credentialDevice: UUID?
    @State private var credentialMessage = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Switch password", systemImage: "key.fill").font(.headline)
                        Picker("Switch", selection: $credentialDevice) {
                            Text("Choose a switch").tag(nil as UUID?)
                            ForEach(bluetooth.devices) { device in
                                Text("\(device.name.isEmpty ? "Nearby switch" : device.name) · \(device.id.uuidString.suffix(8))").tag(Optional(device.id))
                            }
                        }
                        .onChange(of: credentialDevice) { _ in password = ""; credentialMessage = "" }
                        SecureField("8 ASCII characters", text: $password)
                            .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("master.password")
                        HStack {
                            Button("Save password") {
                                if let id = credentialDevice, bluetooth.setPassword(password, for: id) {
                                    password = ""; credentialMessage = "Saved on this iPhone"
                                }
                            }.disabled(credentialDevice == nil || (try? SwitchProtocol.eightASCII(password)) == nil).accessibilityIdentifier("master.save")
                            Spacer()
                            Button("Forget password") {
                                if let id = credentialDevice, bluetooth.setPassword("", for: id) {
                                    password = ""; credentialMessage = "Password removed"
                                }
                            }.disabled(credentialDevice == nil)
                        }.font(.subheadline).frame(minHeight: 44)
                        Text(credentialMessage).font(.caption).foregroundColor(Theme.muted)
                        Text("Enter the command password from this switch’s build.")
                            .font(.caption).foregroundColor(Theme.muted)
                    }.panel()
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
                            .disabled(bluetooth.activeID != nil).accessibilityIdentifier("demo.toggle")
                        Text(bluetooth.activeID != nil ? "Wait for the current operation to finish." : "Try the interface with six sample switches. Demo mode never sends Bluetooth commands.")
                            .font(.footnote).foregroundColor(Theme.muted)
                    }.panel()
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Private by design", systemImage: "lock.shield").font(.headline)
                        Text("Switch control goes directly from this iPhone over Bluetooth. No server or account is needed. Your real switch names are remembered on this phone.")
                            .font(.subheadline).foregroundColor(Theme.muted)
                    }.panel()
                    VStack(alignment: .leading, spacing: 16) {
                        Label("A good connection", systemImage: "dot.radiowaves.left.and.right").font(.headline)
                        Text("Keep your switch nearby and powered on. If it won’t connect, disconnect it from the Raspberry Pi first. Nultra briefly connects for a new name lookup or your requested change, then immediately disconnects. Power and battery updates come from broadcasts.")
                            .font(.subheadline).foregroundColor(Theme.muted)
                    }.panel()
                    Text("VERSION 0.3 · PERSONAL EDITION").font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.5).foregroundColor(Theme.muted).frame(maxWidth: .infinity)
                }.padding(24)
            }.background(Theme.background.ignoresSafeArea())
                .navigationTitle("Settings").navigationBarTitleDisplayModeCompat()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark).tint(Theme.mint)
    }
}
