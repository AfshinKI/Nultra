import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bluetooth: BluetoothStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    @State private var credentialDevice: UUID?
    @State private var credentialMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Discovery", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                        Text("Named switches stay in your list. Blue means seen within 15 seconds; gray means not currently seen. Listening runs automatically while Nultra is open.")
                            .font(.subheadline).foregroundColor(Theme.muted)
                        if bluetooth.unnamedCount > 0 && !bluetooth.demo {
                            Text("\(bluetooth.unnamedCount) devices have not returned a name.").font(.caption)
                        }
                        Button("Retry name discovery") { bluetooth.retryDiscovery() }
                            .disabled(bluetooth.demo || bluetooth.hasWork).frame(minHeight: 44)
                    }.panel()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Shortcuts", systemImage: "square.stack.3d.up.fill").font(.headline)
                        Text("In Apple Shortcuts, search Nultra for Turn All Off, Turn All On, or Set Switch Power. Actions open this app and briefly connect to your saved switches.")
                            .font(.subheadline).foregroundColor(Theme.muted)
                    }.panel()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Afshin Kashani").font(.headline).accessibilityIdentifier("developer.name")
                        Text("Developer").font(.caption).foregroundColor(Theme.muted)
                        Link("innovetron.com", destination: URL(string: "https://innovetron.com")!)
                        Text("VERSION \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.0") · PERSONAL EDITION")
                            .font(.caption2).foregroundColor(Theme.muted)
                    }.panel()
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Explore demo mode", isOn: Binding(get: { bluetooth.demo }, set: { bluetooth.setDemo($0) }))
                            .disabled(bluetooth.hasWork).accessibilityIdentifier("demo.toggle")
                        Text("Demo controls never send Bluetooth commands. Your saved real switches return when demo mode is turned off.")
                            .font(.caption).foregroundColor(Theme.muted)
                    }.panel()
                }.padding(16)
            }.background(Theme.background.ignoresSafeArea())
                .navigationTitle("Menu").navigationBarTitleDisplayModeCompat()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onDisappear { password = "" }
                .alert("Needs attention", isPresented: Binding(
                    get: { bluetooth.errorMessage != nil }, set: { if !$0 { bluetooth.errorMessage = nil } }
                )) { Button("OK") { bluetooth.errorMessage = nil } }
                message: { Text(bluetooth.errorMessage ?? "") }
        }.preferredColorScheme(.dark).tint(Theme.mint)
    }
}
