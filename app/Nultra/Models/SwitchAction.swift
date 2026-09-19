import Foundation

/// Shared validation for app and Shortcuts commands; never silently targets a different switch.
enum SwitchAction {
    static func targets(requested: [UUID]?, known: [KnownSwitch]) throws -> [UUID] {
        let valid = Set(known.map(\.id))
        let ids = requested ?? known.map(\.id)
        guard !ids.isEmpty else { throw Failure.noSwitches }
        guard ids.allSatisfy({ valid.contains($0) }) else { throw Failure.unknownSwitch }
        var unique = Set<UUID>()
        return ids.filter { unique.insert($0).inserted }
    }
    enum Failure: LocalizedError {
        case noSwitches, unknownSwitch, demo, busy, interrupted, bluetooth(String), partial(Int, Int)
        var errorDescription: String? {
            switch self {
            case .noSwitches: return "Open Nultra near your switches once to learn their names first."
            case .unknownSwitch: return "This switch is no longer saved in Nultra. Select it again in Shortcuts."
            case .demo: return "Turn off demo mode in Nultra before running a switch shortcut."
            case .busy: return "Nultra is handling another operation. Try again when it finishes."
            case .interrupted: return "The operation was interrupted. Keep Nultra open until it finishes."
            case .bluetooth(let message): return message
            case .partial(let success, let total): return "Updated \(success) of \(total) switches. Check Bluetooth and switch range, then retry."
            }
        }
    }
}
