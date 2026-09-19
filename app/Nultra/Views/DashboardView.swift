import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var bluetooth: BluetoothStore
    @State private var selected: SwitchDevice?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if bluetooth.demo {
                        Label("DEMO · No physical switches are controlled", systemImage: "sparkles")
                            .font(.caption.weight(.semibold)).foregroundColor(Theme.mint)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    hero
                    HStack {
                        Text("Your switches").font(.title2.bold())
                        Spacer()
                        Text(String(format: "%02d", bluetooth.devices.count))
                            .font(.system(.callout, design: .monospaced)).foregroundColor(Theme.muted)
                    }
                    if bluetooth.devices.isEmpty { emptyState }
                    else {
                        LazyVStack(spacing: 14) {
                            ForEach(bluetooth.devices) { device in
                                DeviceCard(device: device, active: bluetooth.activeID == device.id,
                                           phase: bluetooth.phase) { selected = device }
                            }
                        }
                    }
                    Label("Direct from your iPhone. Just Bluetooth.", systemImage: "iphone.radiowaves.left.and.right")
                        .font(.footnote).foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .automatic)
            .sheet(item: $selected) { device in DeviceDetailView(deviceID: device.id).environmentObject(bluetooth) }
            .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(bluetooth) }
            .alert("Switch needs attention", isPresented: Binding(
                get: { bluetooth.errorMessage != nil && selected == nil },
                set: { if !$0 { bluetooth.errorMessage = nil } }
            )) { Button("OK", role: .cancel) { bluetooth.errorMessage = nil } }
            message: { Text(bluetooth.errorMessage ?? "") }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("BrandMark").resizable().scaledToFill().frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 13)).accessibilityHidden(true)
            Text("nultra").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-1)
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3)
                    .frame(width: 48, height: 48).background(Theme.surface, in: Circle())
            }.accessibilityLabel("Settings")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 7) {
                Circle().fill(Theme.mint).frame(width: 6, height: 6)
                Text(bluetooth.demo ? "A LITTLE PREVIEW" : "YOUR SPACE, CONNECTED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(Theme.mint)
            }
            Text("A little touch.\nA brighter space.")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold)).tracking(-1.2)
                .fixedSize(horizontal: false, vertical: true)
            Text(bluetooth.demo ? "Explore your switches, without connecting a thing." : bluetooth.radio)
                .font(.subheadline).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if !bluetooth.demo {
                Button {
                    bluetooth.scanning ? bluetooth.stopScan() : bluetooth.startScan()
                } label: {
                    HStack(spacing: 10) {
                        if bluetooth.scanning { ProgressView().tint(Theme.background) }
                        else { Image(systemName: "dot.radiowaves.left.and.right") }
                        Text(bluetooth.scanning ? "Stop scanning" : "Find switches")
                    }
                }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.07, green: 0.19, blue: 0.20), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.mint.opacity(0.12), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.mint).padding(20)
                .background(Theme.mint.opacity(0.06), in: Circle())
            Text(bluetooth.scanning ? "Looking around…" : "Make yourself at home")
                .font(.title3.weight(.semibold))
            Text(bluetooth.scanning ? "Keep your switches powered on and nearby." : "Find a nearby Nultra switch to get started. Your iPhone takes care of the connection.")
                .font(.subheadline).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            if !bluetooth.scanning {
                Button("Explore the demo") { bluetooth.setDemo(true) }
                    .font(.subheadline.weight(.semibold)).padding(.vertical, 8)
            }
        }.frame(maxWidth: .infinity).panel()
    }
}

private struct DeviceCard: View {
    let device: SwitchDevice
    let active: Bool
    let phase: BluetoothStore.Phase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Image(systemName: device.isOn == true ? "lightbulb.fill" : "lightbulb")
                        .font(.title2).foregroundColor(device.isOn == true ? Theme.mint : Theme.muted)
                        .frame(width: 48, height: 48)
                        .background(Theme.mint.opacity(device.isOn == true ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 16))
                    Spacer()
                    Label(device.battery.map { "\($0)%" } ?? "—", systemImage: "battery.100")
                        .font(.caption.monospacedDigit()).foregroundColor(Theme.muted)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.name).font(.headline).foregroundColor(.white).lineLimit(2)
                        Text(active ? phase.label : "Tap to connect")
                            .font(.caption).foregroundColor(active ? Theme.mint : Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.body.weight(.medium)).foregroundColor(Theme.mint)
                }
            }.panel()
        }.buttonStyle(.plain)
        .accessibilityLabel("\(device.name), \(active ? phase.label : "tap to connect")")
    }
}
