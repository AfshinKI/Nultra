import Foundation

/// Retains accepted work independently of the caller. Errors after acceptance are silent.
@MainActor final class SilentCommandRunner {
    nonisolated init() {}
    private var task: Task<Void, Never>?
    var isRunning: Bool { task != nil }

    func submit(operation: @escaping @MainActor () async throws -> Void,
                completion: @escaping @MainActor () -> Void) throws {
        guard task == nil else { throw SwitchAction.Failure.busy }
        task = Task { @MainActor [self] in
            defer { task = nil; completion() }
            do {
                try Task.checkCancellation()
                try await operation()
            } catch {
                // The request has already been accepted; do not surface late dialogs.
            }
        }
    }

    func cancel() { task?.cancel() }
}
