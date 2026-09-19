import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bluetooth: BluetoothStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var server = ServerConfiguration()
    @State private var batteryEnabled = BatteryNotifications.shared.enabled
    @State private var batteryThreshold = BatteryNotifications.shared.threshold
    @State private var notificationStatus = ""

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
                        Label("Backup server", systemImage: "network").font(.headline)
                        Toggle("Enable server fallback", isOn: $server.enabled)
                            .accessibilityIdentifier("server.enabled")
                        TextField("http://hostname:port", text: $server.address).asciiEntry()
                            .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("server.address")
                        Text("Uses your Nultra web server when a saved switch is outside Bluetooth range. Enter your server address and port; no address is preset. HTTP is unencrypted: use it only on a trusted home network.")
                            .font(.caption).foregroundColor(Theme.muted)
                        Button("Save server") { bluetooth.saveServer(server); server = bluetooth.serverConfiguration }
                            .accessibilityIdentifier("server.save")
                        Button("Check server and load switches") { Task { await bluetooth.checkServer() } }
                            .disabled(!bluetooth.serverConfiguration.enabled || bluetooth.checkingServer || bluetooth.demo)
                            .accessibilityIdentifier("server.check")
                        Text(bluetooth.serverStatus).font(.caption).foregroundColor(Theme.muted)
                        if !bluetooth.serverDevices.isEmpty {
                            Text("Switch mapping").font(.subheadline.bold())
                            Text("Automatic matching requires an exact, unique name. Once used, the server address is remembered. Select a switch explicitly if names differ.")
                                .font(.caption).foregroundColor(Theme.muted)
                            ForEach(bluetooth.visibleDevices) { device in
                                Picker(device.name, selection: Binding(
                                    get: { bluetooth.serverConfiguration.mappings[device.id.uuidString] ?? "" },
                                    set: { bluetooth.mapServer(device.id, address: $0); server = bluetooth.serverConfiguration }
                                )) {
                                    Text("Match by name").tag("")
                                    ForEach(bluetooth.serverDevices.filter { $0.validAddress && !$0.name.isEmpty }) { row in
                                        Text("\(row.name) · \(row.address)").tag(row.address)
                                    }
                                }.font(.caption)
                            }
                        }
                    }.panel().disabled(bluetooth.hasWork)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Battery alerts", systemImage: "battery.25percent").font(.headline)
                        Toggle("Low battery notifications", isOn: Binding(
                            get: { batteryEnabled },
                            set: { value in
                                batteryEnabled = value
                                BatteryNotifications.shared.enabled = value
                                if value {
                                    BatteryNotifications.shared.requestPermission { granted in
                                        notificationStatus = granted ? "Notifications allowed" : "Allow notifications in iPhone Settings → Nultra → Notifications."
                                    }
                                }
                            }
                        )).accessibilityIdentifier("battery.enabled")
                        Stepper("Notify at or below \(batteryThreshold)%", value: $batteryThreshold, in: 1...50)
                            .onChange(of: batteryThreshold) { BatteryNotifications.shared.threshold = $0 }
                            .accessibilityIdentifier("battery.threshold")
                        Text("Default 5%. One alert per switch until its battery recovers by 10 percentage points above the alert threshold. Alerts use new readings received by Nultra; no monitoring while the app is stopped.")
                            .font(.caption).foregroundColor(Theme.muted)
                        if !notificationStatus.isEmpty { Text(notificationStatus).font(.caption).foregroundColor(Theme.muted) }
                    }.panel()
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Discovery", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                        Text("Named switches stay in your list. Blue means recently seen by Bluetooth or available through your enabled server; gray means neither route is currently available. Listening runs automatically while Nultra is open.")
                            .font(.subheadline).foregroundColor(Theme.muted)
                        if bluetooth.unnamedCount > 0 && !bluetooth.demo {
                            Text("\(bluetooth.unnamedCount) devices have not returned a name.").font(.caption)
                        }
                        Button("Retry name discovery") { bluetooth.retryDiscovery() }
                            .disabled(bluetooth.demo || bluetooth.hasWork).frame(minHeight: 44)
                    }.panel()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Widgets and Shortcuts", systemImage: "square.stack.3d.up.fill").font(.headline)
                        Text("Add Nultra lights from the Home Screen widget gallery (iOS 17+). Small shows four bulbs, medium eight, and large sixteen. Long-press the widget → Edit Widget to choose lights. Tapping opens Nultra to apply the change. Widget state is last reported, not live.\n\nIn Apple Shortcuts, search Nultra for Turn All Off, Turn All On, or Set Switch Power. Actions run in the background and disconnect after each Bluetooth command. Open Nultra once to grant Bluetooth and local-network access. Server commands report queued status because the server cannot confirm completion.")
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
                .onAppear { server = bluetooth.serverConfiguration }
                .onDisappear { password = "" }
                .alert("Needs attention", isPresented: Binding(
                    get: { bluetooth.errorMessage != nil }, set: { if !$0 { bluetooth.errorMessage = nil } }
                )) { Button("OK") { bluetooth.errorMessage = nil } }
                message: { Text(bluetooth.errorMessage ?? "") }
        }.preferredColorScheme(.dark).tint(Theme.mint)
    }
}
