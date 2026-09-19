import Foundation
import UserNotifications

/// Observed readings only; no background polling or remote push service.
final class BatteryNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BatteryNotifications()
    private let defaults = UserDefaults.standard
    private var pending = Set<UUID>()
    var enabled: Bool {
        get { defaults.bool(forKey: "batteryAlerts.enabled") }
        set { defaults.set(newValue, forKey: "batteryAlerts.enabled") }
    }
    var threshold: Int {
        get { (defaults.object(forKey: "batteryAlerts.threshold") as? Int).map { max(1, min(50, $0)) } ?? 5 }
        set { defaults.set(max(1, min(50, newValue)), forKey: "batteryAlerts.threshold") }
    }
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    func observe(_ device: SwitchDevice) {
        guard device.visible, let battery = device.battery, (0...100).contains(battery), !pending.contains(device.id) else { return }
        let key = "batteryAlerts.state." + device.id.uuidString
        let previous = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(BatteryAlertPolicy.self, from: $0) } ?? BatteryAlertPolicy()
        var next = previous
        let alert = next.observe(battery, threshold: threshold)
        if !alert {
            if next != previous { defaults.set(try? JSONEncoder().encode(next), forKey: key) }
            return
        }
        guard enabled else { return }
        pending.insert(device.id)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard self.enabled, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    self.pending.remove(device.id); return
                }
                let content = UNMutableNotificationContent()
                content.title = "\(device.name) battery is low"
                content.body = "Battery is at \(battery)%. Replace or recharge the switch battery."
                content.sound = .default
                let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request) { error in
                    DispatchQueue.main.async {
                        self.pending.remove(device.id)
                        if error == nil { self.defaults.set(try? JSONEncoder().encode(next), forKey: key) }
                    }
                }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
