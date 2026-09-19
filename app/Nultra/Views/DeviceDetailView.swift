import SwiftUI

struct DeviceDetailView: View {
    let deviceID: UUID
    @EnvironmentObject private var bluetooth: BluetoothStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var newName = ""
    @State private var hasSavedPassword = false
    @State private var editingPassword = false
    @State private var renaming = false

    private var device: SwitchDevice? { bluetooth.devices.first { $0.id == deviceID } }
    private var active: Bool { bluetooth.activeID == deviceID }
    private var ready: Bool { active && bluetooth.phase == .ready }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let device = device {
                        Image(systemName: device.isOn == true ? "lightbulb.fill" : "lightbulb")
                            .font(.system(size: 52, weight: .light)).foregroundColor(Theme.mint)
                            .frame(width: 120, height: 120)
                            .background(Theme.mint.opacity(0.08), in: Circle()).padding(.top, 18)
                        VStack(spacing: 8) {
                            Text(device.name).font(.system(.title, design: .rounded).bold()).multilineTextAlignment(.center)
                            Text(active ? bluetooth.phase.label : "Connect to take control")
                                .foregroundColor(Theme.muted).font(.subheadline)
                            if bluetooth.demo { Text("DEMO SWITCH").font(.caption.bold()).foregroundColor(Theme.mint) }
                        }
                        if active {
                            controls(device)
                        } else if bluetooth.activeID != nil {
                            VStack(spacing: 14) {
                                Text("Another switch is connected. Disconnect it before connecting here.")
                                    .foregroundColor(Theme.muted)
                                Button("Disconnect current switch") { bluetooth.disconnect() }.buttonStyle(PrimaryButton())
                            }.panel()
                        } else {
                            connectionForm
                        }
                        HStack(alignment: .top) {
                            metric("BATTERY", device.battery.map { "\($0)%" } ?? "—")
                            Spacer()
                            metric("SIGNAL", device.signal)
                            Spacer()
                            metric("FIRMWARE", device.firmware ?? "—")
                        }.panel()
                        if let confirmed = device.lastConfirmed {
                            Text("Last read \(confirmed.formatted(date: .omitted, time: .shortened)) · \(device.isOn == true ? "On" : "Off")")
                                .font(.caption).foregroundColor(Theme.muted)
                        } else {
                            Text("Advertisement values are estimates until connected.")
                                .font(.caption).foregroundColor(Theme.muted)
                        }
                        if !active && !bluetooth.demo && hasSavedPassword {
                            Button("Forget saved password", role: .destructive) {
                                bluetooth.forgetPassword(deviceID)
                                hasSavedPassword = bluetooth.savedPasswordExists(for: deviceID)
                                editingPassword = true
                            }.font(.footnote).padding(10)
                        }
                    } else {
                        Text("This switch is no longer in the nearby list. Scan again to find it.")
                    }
                }.padding(24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Switch").navigationBarTitleDisplayModeCompat()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if !bluetooth.demo { hasSavedPassword = bluetooth.savedPasswordExists(for: deviceID) } }
            .onDisappear { password = "" }
            .alert("Switch needs attention", isPresented: Binding(
                get: { bluetooth.errorMessage != nil }, set: { if !$0 { bluetooth.errorMessage = nil } }
            )) { Button("OK", role: .cancel) { bluetooth.errorMessage = nil } }
            message: { Text(bluetooth.errorMessage ?? "") }
        }.preferredColorScheme(.dark).tint(Theme.mint)
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !bluetooth.demo && (!hasSavedPassword || editingPassword) {
                Text("Your switch, securely connected.").font(.headline)
                Text("Enter its 8-character password. It stays in your iPhone’s Keychain.")
                    .font(.subheadline).foregroundColor(Theme.muted)
                SecureField("Switch password", text: $password).asciiEntry()
                    .padding(16).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                Button("Save & connect") {
                    bluetooth.connect(deviceID, enteredPassword: password)
                    password = ""
                    hasSavedPassword = bluetooth.savedPasswordExists(for: deviceID)
                }.buttonStyle(PrimaryButton()).disabled((try? SwitchProtocol.eightASCII(password)) == nil)
            } else {
                Button(bluetooth.demo ? "Try this switch" : "Connect to switch") { bluetooth.connect(deviceID) }
                    .buttonStyle(PrimaryButton())
                if !bluetooth.demo {
                    Button("Use a different password") { editingPassword = true }.font(.footnote)
                }
            }
        }.panel()
    }

    private func controls(_ device: SwitchDevice) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text(device.isOn == true ? "Power is on" : "Power is off").font(.title3.weight(.semibold))
                Spacer()
                if !ready { ProgressView().tint(Theme.mint) }
            }
            HStack(spacing: 12) {
                Button { bluetooth.setPower(false) } label: { Label("Off", systemImage: "power") }
                    .buttonStyle(PrimaryButton(subdued: device.isOn != false))
                Button { bluetooth.setPower(true) } label: { Label("On", systemImage: "bolt.fill") }
                    .buttonStyle(PrimaryButton(subdued: device.isOn != true))
            }.disabled(!ready)
            if !ready { Text("Waiting for confirmation from the switch.").font(.caption).foregroundColor(Theme.muted) }
            HStack {
                Button("Refresh", systemImageCompat: "arrow.clockwise") { bluetooth.refresh() }.disabled(!ready)
                Spacer()
                Button("Rename") { newName = device.name; renaming.toggle() }.disabled(!ready)
                Spacer()
                Button("Disconnect") { bluetooth.disconnect() }.disabled(bluetooth.phase == .disconnecting)
            }.font(.caption.weight(.semibold))
            if renaming {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("8-character name", text: $newName).asciiEntry()
                        .padding(14).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                    Text("Exactly 8 ASCII characters, for example DESKLAMP.").font(.caption).foregroundColor(Theme.muted)
                    Button("Save name") { bluetooth.rename(newName); renaming = false }
                        .buttonStyle(PrimaryButton(subdued: true))
                        .disabled(!ready || (try? SwitchProtocol.eightASCII(newName)) == nil || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.panel()
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundColor(Theme.muted)
            Text(value).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    @ViewBuilder func navigationBarTitleDisplayModeCompat() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, systemImageCompat image: String, action: @escaping () -> Void) {
        self.init(action: action) { SwiftUI.Label(title, systemImage: image) }
    }
}
