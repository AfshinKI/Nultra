import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var bluetooth: BluetoothStore
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selected: SwitchDevice?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image("BrandMark").resizable().frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                        Text("nultra").font(.system(size: 26, weight: .semibold, design: .rounded))
                        Spacer()
                        Button { showingSettings = true } label: {
                            Image(systemName: "line.3.horizontal").frame(width: 44, height: 44)
                        }.accessibilityLabel("Menu").accessibilityIdentifier("settings")
                    }
                    if bluetooth.demo {
                        Text("DEMO · No physical switches controlled")
                            .font(.caption).foregroundColor(Theme.mint).accessibilityIdentifier("demo.banner")
                    }
                    HStack(spacing: 10) {
                        Button { bluetooth.setAllPower(false) } label: { Label("All Off", systemImage: "lightbulb") }
                            .buttonStyle(CompactPowerButton(on: false)).accessibilityIdentifier("all.off")
                        Button { bluetooth.setAllPower(true) } label: { Label("All On", systemImage: "lightbulb.fill") }
                            .buttonStyle(CompactPowerButton(on: true)).accessibilityIdentifier("all.on")
                    }.disabled(bluetooth.hasWork || bluetooth.visibleDevices.isEmpty)
                    HStack {
                        Text(bluetooth.demo ? "Your switches" : bluetooth.scanning ? "Listening" : bluetooth.radio)
                            .accessibilityIdentifier("scan.status")
                        Spacer()
                        Text("\(bluetooth.visibleDevices.count) saved")
                    }.font(.caption).foregroundColor(Theme.muted)
                    if let message = bluetooth.bulkStatus {
                        Text(message).font(.caption).foregroundColor(Theme.mint).accessibilityIdentifier("bulk.status")
                    }
                    ScenesPanel()
                    if bluetooth.visibleDevices.isEmpty {
                        VStack(spacing: 18) {
                            Image(systemName: "dot.radiowaves.left.and.right").font(.largeTitle).foregroundColor(Theme.mint)
                            Text("Waiting for named switches").font(.title3.bold())
                            Text(bluetooth.radio).font(.subheadline).foregroundColor(Theme.muted)
                            Text("Listening starts automatically. A switch appears here once its real name has been read.")
                                .font(.subheadline).foregroundColor(Theme.muted).multilineTextAlignment(.center)
                            Button("Explore the demo") { bluetooth.setDemo(true) }
                        }.frame(maxWidth: .infinity).panel().padding(.top, 30)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: textSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                            ForEach(bluetooth.visibleDevices) { device in
                                DeviceCard(device: device, busy: bluetooth.isBusy(device.id), online: bluetooth.online(device),
                                           detail: { selected = device },
                                           power: { bluetooth.setPower(device.id, !(device.isOn ?? false)) })
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
                get: { bluetooth.errorMessage != nil && selected == nil && !showingSettings },
                set: { if !$0 { bluetooth.errorMessage = nil } }
            )) { Button("OK", role: .cancel) { bluetooth.errorMessage = nil } }
            message: { Text(bluetooth.errorMessage ?? "") }
        }
    }
}

private struct DeviceCard: View {
    let device: SwitchDevice
    let busy: Bool
    let online: Bool
    let detail: () -> Void
    let power: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(online ? Theme.online : Theme.muted.opacity(0.45)).frame(width: 6, height: 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(online ? "Online" : "Offline")
                    .accessibilityIdentifier("presence.\(device.name)")
                if device.lookupError != nil {
                    Image(systemName: "exclamationmark.circle").foregroundColor(.orange)
                        .accessibilityLabel("Last operation failed; open switch details")
                }
                Spacer(minLength: 4)
                SignalBars(count: online ? device.signalBars : 0)
                    .accessibilityIdentifier("signal.\(device.name)")
                BatteryGlyph(level: device.battery, fill: device.batteryFill, low: device.batteryLow)
            }.font(.system(size: 10))
            HStack(spacing: 2) {
                Button(action: detail) {
                    Text(device.name).font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundColor(.white)
                    .accessibilityLabel("\(device.name), details and rename")
                    .accessibilityIdentifier("device.\(device.name)")
                Button(action: power) {
                    ZStack {
                        if busy { ProgressView().tint(Theme.mint) }
                        else {
                            Image(systemName: device.isOn == true ? "lightbulb.fill" : "lightbulb")
                                .font(.system(size: 25))
                                .foregroundColor(device.isOn == true ? Theme.bulb : Theme.muted)
                                .shadow(color: device.isOn == true ? Theme.bulb.opacity(0.7) : .clear, radius: 8)
                        }
                    }.frame(width: 44, height: 44)
                        .background(device.isOn == true ? Theme.bulb.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(busy)
                    .accessibilityLabel(busy ? "Updating \(device.name)" : "\(device.name), \(device.powerLabel), turn \(device.isOn == true ? "off" : "on")")
                    .accessibilityIdentifier("toggle.\(device.name)")
            }
        }.padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(device.isOn == true ? Theme.bulb.opacity(0.20) : .white.opacity(0.05), lineWidth: 1))
    }
}

struct SignalBars: View {
    let count: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < count ? Theme.muted : Theme.muted.opacity(0.2))
                    .frame(width: 3, height: CGFloat(4 + index * 4))
            }
        }.frame(width: 13, height: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count == 0 ? "No signal" : "Signal \(count) of 3 bars")
    }
}

struct BatteryGlyph: View {
    let level: Int?
    let fill: Double
    let low: Bool
    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).stroke(Theme.muted.opacity(0.7), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1)
                    .fill(level == nil ? .clear : low ? .red : .green)
                    .frame(width: 16 * fill, height: 6).padding(.leading, 2)
            }.frame(width: 20, height: 10)
            Capsule().fill(Theme.muted.opacity(0.7)).frame(width: 2, height: 4)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(level == nil ? "Battery unknown" : low ? "Battery low" : "Battery available; percentage in switch details")
    }
}

struct CompactPowerButton: ButtonStyle {
    let on: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundColor(on ? Theme.bulb : Theme.muted)
            .background(on ? Theme.bulb.opacity(0.12) : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}
