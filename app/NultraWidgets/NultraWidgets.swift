import SwiftUI
import WidgetKit

struct LightEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let configuration: ChooseWidgetLights
}

struct LightProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LightEntry {
        LightEntry(date: Date(), snapshot: WidgetSnapshot(date: Date(), lights: [
            WidgetLight(id: UUID(), name: "DESKLAMP", isOn: true),
            WidgetLight(id: UUID(), name: "BEDROOM1", isOn: false),
            WidgetLight(id: UUID(), name: "KITCHEN1", isOn: true),
            WidgetLight(id: UUID(), name: "HALLWAY1", isOn: false)
        ]), configuration: ChooseWidgetLights())
    }
    func snapshot(for configuration: ChooseWidgetLights, in context: Context) async -> LightEntry {
        LightEntry(date: Date(), snapshot: WidgetSnapshot.load(), configuration: configuration)
    }
    func timeline(for configuration: ChooseWidgetLights, in context: Context) async -> Timeline<LightEntry> {
        let entry = await snapshot(for: configuration, in: context)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
}

struct LightWidgetView: View {
    let entry: LightEntry
    @Environment(\.widgetFamily) private var family
    private var columns: Int { family == .systemSmall ? 2 : 4 }
    private var rows: Int { family == .systemLarge ? 4 : 2 }
    private var lights: [WidgetLight] {
        entry.snapshot.selected(entry.configuration.lights?.map(\.id) ?? [], limit: columns * rows)
    }
    var body: some View {
        VStack(spacing: 4) {
            if lights.isEmpty {
                Image(systemName: "lightbulb").font(.title)
                Text("Open Nultra to discover lights, then edit this widget to choose them.")
                    .font(.caption).multilineTextAlignment(.center)
            } else {
                Grid(horizontalSpacing: 6, verticalSpacing: 4) {
                    ForEach(0..<rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                if index < lights.count {
                                    let light = lights[index]
                                    Button(intent: WidgetPowerIntent(id: light.id, on: light.commandPower)) {
                                        VStack(spacing: 3) {
                                            Image(systemName: light.fixedPower != nil ? "power" : light.members != nil ? "square.stack.3d.up.fill" : light.isOn == true ? "lightbulb.fill" : "lightbulb")
                                                .font(.system(size: family == .systemLarge ? 27 : 23))
                                                .foregroundStyle(light.isOn == true ? Color.yellow : Color.gray)
                                            Text(light.name).font(.system(size: 10, weight: .medium))
                                                .lineLimit(1).minimumScaleFactor(0.7)
                                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }.buttonStyle(.plain)
                                    .accessibilityLabel("\(light.name), last reported \(light.isOn.map { $0 ? "on" : "off" } ?? "unknown"). Turn \(light.commandPower ? "on" : "off")")
                                } else { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity) }
                            }
                        }
                    }
                }
                Text(WidgetSnapshot.commandStatus ?? "Last reported · not live").font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .containerBackground(Color(red: 0.03, green: 0.06, blue: 0.09), for: .widget)
    }
}

@main
struct NultraLightsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSnapshot.kind, intent: ChooseWidgetLights.self, provider: LightProvider()) { entry in
            LightWidgetView(entry: entry)
        }
        .configurationDisplayName("Nultra lights")
        .description("Choose lights, all switches, or scenes. Tap to change power in the background. State is last reported, not live.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
