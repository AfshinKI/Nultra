#if os(iOS)
import BackgroundTasks
import Foundation

@MainActor
final class BackgroundRefresh {
    static let shared = BackgroundRefresh()
    static let identifier = "com.afshinki.nultra.refresh"
    private var work: Task<Void, Never>?
    private var registered = false
    private init() {}
    func register() {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            Task { @MainActor in self.run(task) }
        }
        schedule()
    }
    func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        guard RefreshSettings().enabled else { work?.cancel(); return }
        guard ServerConfiguration.load().enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date().addingTimeInterval(Double(RefreshSettings().minutes * 60))
        do { try BGTaskScheduler.shared.submit(request) }
        catch { UserDefaults.standard.set("System did not accept a refresh request. Check Background App Refresh in iPhone Settings.", forKey: "refresh.status") }
    }
    private func run(_ task: BGTask) {
        schedule()
        let operation = Task { @MainActor in
            let success = await BluetoothStore.shared.refreshInBackground()
            task.setTaskCompleted(success: success)
        }
        work = operation
        task.expirationHandler = { operation.cancel() }
    }
}
#endif
