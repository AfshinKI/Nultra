import Foundation

@main struct WidgetChecks {
    static func main() throws {
        let lights = (0..<20).map { WidgetLight(id: UUID(), name: "LIGHT\($0)", isOn: $0 % 2 == 0) }
        let snapshot = WidgetSnapshot(date: Date(), lights: lights)
        assert(snapshot.selected([], limit: 4).count == 4)
        assert(snapshot.selected([], limit: 8).count == 8)
        assert(snapshot.selected([], limit: 16).count == 16)
        assert(snapshot.selected([lights[7].id, lights[2].id, lights[7].id, UUID()], limit: 4).map(\.id) == [lights[7].id, lights[2].id])
        let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        assert(restored == snapshot)
        let legacy = "{\"date\":0,\"lights\":[{\"id\":\"\(lights[0].id.uuidString)\",\"name\":\"LAMP0001\",\"isOn\":true}]}".data(using: .utf8)!
        let old = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)
        assert(old.lights[0].members == nil && old.lights[0].isOn == true)
        let allOn = WidgetLight(id: WidgetLight.allOnID, name: "All On", isOn: true, members: lights.map(\.id), fixedPower: true)
        let allOff = WidgetLight(id: WidgetLight.allOffID, name: "All Off", isOn: false, members: lights.map(\.id), fixedPower: false)
        assert(allOn.commandPower && !allOff.commandPower)
        assert(WidgetLight.groupState(lights) == nil)
        assert(WidgetLight.groupState([]) == nil)
        let grouped = WidgetSnapshot(date: Date(), lights: lights + [allOn, allOff])
        assert(grouped.selected([WidgetLight.allOffID, WidgetLight.allOnID], limit: 4).map(\.id) == [WidgetLight.allOffID, WidgetLight.allOnID])
        var policy = BatteryAlertPolicy()
        assert(policy.observe(5, threshold: 5))
        for value in [4, 7, 3, 8, 5, 0, 14] { assert(!policy.observe(value, threshold: 5)) }
        policy = try JSONDecoder().decode(BatteryAlertPolicy.self, from: JSONEncoder().encode(policy))
        assert(!policy.observe(5, threshold: 5))
        assert(!policy.observe(15, threshold: 5))
        assert(policy.observe(4, threshold: 5))
        print("Passed widget selection, snapshot round-trip, battery jitter and persistence checks")
    }
}
