import SwiftUI

struct ScenesPanel: View {
    @EnvironmentObject private var bluetooth: BluetoothStore
    @State private var editing: SwitchScene?
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Scenes").font(.subheadline.bold())
                Spacer()
                Button { editing = SwitchScene(name: "", members: []) } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }.accessibilityLabel("Add scene").accessibilityIdentifier("scene.add")
                    .disabled(bluetooth.visibleDevices.isEmpty)
            }
            ForEach(bluetooth.scenes) { scene in
                HStack {
                    Button { editing = scene } label: {
                        VStack(alignment: .leading) {
                            Text(scene.name).font(.subheadline.bold())
                            Text("\(scene.members.count) lights · Edit").font(.caption)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityLabel("Edit scene \(scene.name)")
                    Button("Off") { bluetooth.scenePower(scene, false) }.disabled(bluetooth.hasWork)
                    Button("On") { bluetooth.scenePower(scene, true) }.disabled(bluetooth.hasWork)
                }.padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }.sheet(item: $editing) { scene in SceneEditor(scene: scene).environmentObject(bluetooth) }
    }
}

struct SceneEditor: View {
    @EnvironmentObject private var bluetooth: BluetoothStore
    @Environment(\.dismiss) private var dismiss
    @State var scene: SwitchScene
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Scene name", text: $scene.name).accessibilityIdentifier("scene.name")
                Section("Lights (may belong to multiple scenes)") {
                    ForEach(bluetooth.visibleDevices) { device in
                        Toggle(device.name, isOn: Binding(get: { scene.members.contains(device.id) }, set: { on in
                            scene.members.removeAll { $0 == device.id }
                            if on { scene.members.append(device.id) }
                        }))
                    }
                }
                if bluetooth.scenes.contains(where: { $0.id == scene.id }) {
                    Button("Delete scene", role: .destructive) { deleting = true }
                }
            }.navigationTitle("Scene")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { bluetooth.saveScene(scene); dismiss() }
                            .disabled(scene.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scene.members.isEmpty)
                            .accessibilityIdentifier("scene.save")
                    }
                }
                .alert("Delete \(scene.name)?", isPresented: $deleting) {
                    Button("Delete", role: .destructive) { bluetooth.deleteScene(scene.id); dismiss() }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("The lights and their other scenes are kept.") }
        }.preferredColorScheme(.dark).tint(Theme.mint)
    }
}

struct DeviceScenesView: View {
    let deviceID: UUID
    @EnvironmentObject private var bluetooth: BluetoothStore
    @State private var editing: SwitchScene?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scenes").font(.headline)
            if bluetooth.scenes.isEmpty { Text("Create a scene from the home screen.").font(.caption) }
            ForEach(bluetooth.scenes) { scene in
                HStack {
                    Toggle(scene.name, isOn: Binding(get: { scene.members.contains(deviceID) }, set: { on in
                        var changed = scene
                        changed.members.removeAll { $0 == deviceID }
                        if on { changed.members.append(deviceID) }
                        if changed.members.isEmpty { editing = changed }
                        else { bluetooth.saveScene(changed) }
                    }))
                    Button("Edit") { editing = scene }
                }
            }
            Text("A scene needs at least one light. Edit to replace its last light or delete the scene.").font(.caption).foregroundColor(Theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
            .sheet(item: $editing) { SceneEditor(scene: $0).environmentObject(bluetooth) }
    }
}
