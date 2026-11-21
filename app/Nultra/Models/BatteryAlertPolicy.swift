import Foundation

/// One alert per low-battery episode. A ten-point recovery rearms the alert.
struct BatteryAlertPolicy: Codable, Equatable {
    var alerted = false
    var recoveryLevel = 15

    mutating func observe(_ battery: Int?, threshold: Int) -> Bool {
        guard let battery = battery, (0...100).contains(battery) else { return false }
        let threshold = max(1, min(50, threshold))
        if alerted {
            if battery >= recoveryLevel { alerted = false }
            return false
        }
        guard battery <= threshold else { return false }
        alerted = true
        recoveryLevel = threshold + 10
        return true
    }
}
