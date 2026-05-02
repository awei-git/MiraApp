import BackgroundTasks
import MiraBridge

/// Registers and handles BGAppRefreshTask so the app can poll the bridge
/// and fire local notifications while backgrounded.
final class BackgroundRefreshManager {
    static let taskIdentifier = "com.angwei.mira.refresh"
    static let shared = BackgroundRefreshManager()

    private var config: BridgeConfig?
    private var store: ItemStore?
    private var notifications: NotificationManager?

    private init() {}

    /// Call once in App.init() before first scene renders.
    func registerTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self?.handleRefresh(refreshTask)
        }
    }

    /// Call once services are ready (after config/store/notifications are created).
    func configure(config: BridgeConfig, store: ItemStore, notifications: NotificationManager) {
        self.config = config
        self.store = store
        self.notifications = notifications
    }

    /// Schedule the next background refresh.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[BackgroundRefresh] schedule failed: \(error)")
            #endif
        }
    }

    private func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()

        guard let config, let store, let notifications else {
            task.setTaskCompleted(success: false)
            return
        }

        let engine = SyncEngine(config: config, store: store)

        task.expirationHandler = {
            // SyncEngine refresh is quick, nothing to cancel
        }

        engine.refresh {
            notifications.processChanges(items: store.items)

            // Export Apple Health through API first, with iCloud bridge fallback.
            Task {
                await HealthExporter.shared.export(config: config)
                task.setTaskCompleted(success: true)
            }
        }
    }
}
