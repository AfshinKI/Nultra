import Foundation

struct RefreshSettings {
    static let intervals = [15, 30, 60]
    var defaults = UserDefaults.standard
    var enabled: Bool {
        get { defaults.object(forKey: "refresh.enabled") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "refresh.enabled") }
    }
    var minutes: Int {
        get { let value = defaults.integer(forKey: "refresh.minutes"); return Self.intervals.contains(value) ? value : 30 }
        nonmutating set { defaults.set(Self.intervals.contains(newValue) ? newValue : 30, forKey: "refresh.minutes") }
    }
}
