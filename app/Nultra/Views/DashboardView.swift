import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var bluetooth: BluetoothStore
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selected: SwitchDevice?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image("BrandMark").resizable().frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                        Text("nultra").font(.system(size: 26, weight: .semibold, design: .rounded))
                        Spacer()
                        Button { showingSettings = true } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                        }.accessibilityLabel("Settings").accessibilityIdentifier("settings")
                    }
                    if bluetooth.demo {
                        Text("DEMO · No physical switches controlled")
                            .font(.caption).foregroundColor(Theme.mint).accessibilityIdentifier("demo.banner")
                    }
                    HStack {
                        Text(bluetooth.demo ? "Your switches" : bluetooth.scanning ? "Listening · \(bluetooth.devices.count) switches" : "Your switches · \(bluetooth.devices.count)")
                            .font(.subheadline.weight(.medium)).foregroundColor(Theme.muted)
                        Spacer()
                        if !bluetooth.demo {
                            Button(bluetooth.scanning ? "Stop listening" : "Find switches") {
                                bluetooth.scanning ? bluetooth.stopScan() : bluetooth.startScan()
                            }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                        }
                    }
                    if bluetooth.devices.isEmpty {
                        VStack(spacing: 18) {
                            Image(systemName: "dot.radiowaves.left.and.right").font(.largeTitle).foregroundColor(Theme.mint)
                            Text(bluetooth.scanning ? "Finding your switches…" : "Your lights, one touch away.").font(.title3.bold())
                            Text(bluetooth.radio).font(.subheadline).foregroundColor(Theme.muted)
                            Text("New switches get one brief name lookup. After that, Nultra listens without staying connected.")
                                .font(.subheadline).foregroundColor(Theme.muted).multilineTextAlignment(.center)
                            Button("Explore the demo") { bluetooth.setDemo(true) }
                        }.frame(maxWidth: .infinity).panel().padding(.top, 30)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: textSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                            ForEach(bluetooth.devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { device in
                                DeviceCard(device: device, busy: bluetooth.isBusy(device.id),
                                           status: bluetooth.activeID == device.id ? bluetooth.phase.label : "Queued…",
                                           detail: { selected = device },
                                           power: { bluetooth.setPower(device.id, !(device.isOn ?? false)) },
                                           retry: { bluetooth.identify(device.id) })
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
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
}

private struct DeviceCard: View {
    let device: SwitchDevice
    let busy: Bool
    let status: String
    let detail: () -> Void
    let power: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .accessibilityLabel(device.signal)
                Text(device.rssi == 127 ? "—" : "\(device.rssi)")
                Spacer(minLength: 2)
                Image(systemName: device.batterySymbol)
                Text(device.battery.map { "\($0)%" } ?? "—")
            }.font(.system(size: 11)).foregroundColor(Theme.muted)
            Button(action: detail) {
                Text(device.identityKnown ? device.name : "Name pending")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundColor(.white)
                .accessibilityLabel("\(device.name), details and rename")
                .accessibilityIdentifier("device.\(device.name)")
            if device.identityKnown {
                Button(action: power) {
                    HStack(spacing: 7) {
                        if busy { ProgressView().tint(Theme.mint) }
                        else { Image(systemName: device.isOn == true ? "lightbulb.fill" : "lightbulb") }
                        Text(busy ? status : device.powerLabel.uppercased())
                            .font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity, minHeight: 44)
                        .background(device.isOn == true ? Theme.mint.opacity(0.16) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).foregroundColor(device.isOn == true ? Theme.mint : Theme.muted)
                    .disabled(busy)
                    .accessibilityLabel("\(device.name), \(device.powerLabel), turn \(device.isOn == true ? "off" : "on")")
                    .accessibilityIdentifier("toggle.\(device.name)")
            } else {
                Button(busy ? status : "Retry name lookup", action: retry)
                    .font(.caption).frame(minHeight: 44).disabled(busy)
            }
            Group {
                if let error = device.lookupError { Text(error).lineLimit(2) }
                else if let date = device.lastBroadcast, device.stateSource == .advertisement {
                    HStack(spacing: 3) { Text("Seen"); Text(date, style: .relative) }
                } else if device.stateSource == .demo { Text("Demo · Disconnected") }
                else if let date = device.lastConfirmed {
                    HStack(spacing: 3) { Text("Read"); Text(date, style: .relative) }
                } else { Text(device.identityKnown ? "Awaiting broadcast" : "One-time name lookup") }
            }.font(.system(size: 10)).foregroundColor(Theme.muted).padding(.top, 3)
        }.padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.mint.opacity(device.isOn == true ? 0.18 : 0.05), lineWidth: 1))
    }
}
