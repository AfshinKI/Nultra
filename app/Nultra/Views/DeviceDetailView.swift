import SwiftUI

struct DeviceDetailView: View {
    let deviceID: UUID
    @EnvironmentObject private var bluetooth: BluetoothStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renaming = false
    private var device: SwitchDevice? { bluetooth.devices.first { $0.id == deviceID } }
    private var busy: Bool { bluetooth.isBusy(deviceID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let device = device {
                        Image(systemName: device.isOn == true ? "lightbulb.fill" : "lightbulb")
                            .font(.system(size: 44)).foregroundColor(device.isOn == true ? Theme.bulb : Theme.muted)
                            .shadow(color: device.isOn == true ? Theme.bulb.opacity(0.6) : .clear, radius: 12).padding(.top, 16)
                        Text(device.identityKnown ? device.name : "Name lookup pending")
                            .font(.system(.title, design: .rounded).bold()).multilineTextAlignment(.center)
                        if busy {
                            ProgressView().tint(Theme.mint).accessibilityLabel("Updating switch")
                        } else {
                            Text("Disconnected").font(.subheadline).foregroundColor(Theme.muted)
                                .accessibilityIdentifier("connection.status")
                        }
                        if bluetooth.demo { Text("DEMO SWITCH").font(.caption.bold()).foregroundColor(Theme.mint) }
                        if device.identityKnown {
                            VStack(spacing: 16) {
                                Text(device.isOn.map { $0 ? "Power is on" : "Power is off" } ?? "Power not yet observed")
                                    .font(.headline).accessibilityIdentifier("power.state")
                                HStack(spacing: 12) {
                                    Button { bluetooth.setPower(deviceID, false) } label: { Label("Off", systemImage: "lightbulb") }
                                        .buttonStyle(CompactPowerButton(on: false)).accessibilityIdentifier("power.off")
                                    Button { bluetooth.setPower(deviceID, true) } label: { Label("On", systemImage: "lightbulb.fill") }
                                        .buttonStyle(CompactPowerButton(on: true)).accessibilityIdentifier("power.on")
                                }.disabled(busy)
                                Text("Connects only to apply your change, then disconnects immediately.")
                                    .font(.caption).foregroundColor(Theme.muted)
                            }.panel()
                            if !renaming {
                                Button("Rename") { newName = device.name; renaming = true }
                                    .buttonStyle(PrimaryButton(subdued: true)).disabled(busy)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    TextField("8-character name", text: $newName).asciiEntry().accessibilityIdentifier("rename.field")
                                        .padding(14).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                                    Text("Exactly 8 ASCII characters. The switch stays disconnected until you save.")
                                        .font(.caption).foregroundColor(Theme.muted)
                                    Button("Save name") { bluetooth.rename(deviceID, newName); renaming = false }
                                        .buttonStyle(PrimaryButton()).accessibilityIdentifier("rename.save")
                                        .disabled(busy || (try? SwitchProtocol.eightASCII(newName)) == nil || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                                    Button("Cancel") { renaming = false }
                                }.panel()
                            }
                        } else {
                            Text(device.lookupError ?? "A brief connection reads this switch’s real name once.")
                                .font(.subheadline).foregroundColor(Theme.muted)
                            Button("Retry name lookup") { bluetooth.identify(deviceID) }
                                .buttonStyle(PrimaryButton()).disabled(busy)
                        }
                        HStack(alignment: .top) {
                            metric("BATTERY", device.battery.map { "\($0)%" } ?? "—")
                            Spacer()
                            metric("SIGNAL", device.signal)
                            Spacer()
                            metric("FIRMWARE", device.firmware ?? "—")
                        }.panel()
                        if device.stateSource == .advertisement, let date = device.lastBroadcast {
                            HStack { Text("Last broadcast"); Text(date, style: .relative) }
                                .font(.caption).foregroundColor(Theme.muted)
                        }
                    }
                }.padding(20)
            }.background(Theme.background.ignoresSafeArea())
                .navigationTitle("Switch").navigationBarTitleDisplayModeCompat()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .alert("Switch needs attention", isPresented: Binding(
                    get: { bluetooth.errorMessage != nil }, set: { if !$0 { bluetooth.errorMessage = nil } }
                )) { Button("OK", role: .cancel) { bluetooth.errorMessage = nil } }
                message: { Text(bluetooth.errorMessage ?? "") }
        }.preferredColorScheme(.dark).tint(Theme.mint)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(Theme.muted)
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
