import SwiftUI
import MiraBridge
import LocalAuthentication

@main
struct BridgeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var config = BridgeConfig()
    @State private var store = ItemStore()
    @State private var todoStore: TodoStore?
    @State private var syncEngine: SyncEngine?
    @State private var commands: CommandWriter?
    @State private var notifications = NotificationManager()
    @State private var showSplash = true
    @State private var isLocked = true

    init() {
        BackgroundRefreshManager.shared.registerTask()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(hex: 0x008069).ignoresSafeArea()

                if showSplash {
                    SplashView(agentName: config.agentName)
                        .transition(.opacity)
                } else if !config.isProfileSelected {
                    ProfilePickerView()
                        .environment(config)
                        .onChange(of: config.isProfileSelected) { _, selected in
                            if selected && config.isSetup { startServices() }
                        }
                } else if let engine = syncEngine, let cmds = commands, let todos = todoStore {
                    MainTabView()
                        .environment(config)
                        .environment(store)
                        .environment(todos)
                        .environment(notifications)
                        .environment(engine)
                        .environment(cmds)
                        .onAppear { engine.startPolling() }
                        .transition(.opacity)
                } else if config.isProfileSelected {
                    ProgressView("Loading...")
                        .foregroundStyle(.white)
                        .onAppear { startServices() }
                }
            }
            .overlay {
                if isLocked {
                    LockScreenView(agentName: config.agentName) { unlock() }
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                if config.isSetup && config.isProfileSelected {
                    startServices()
                }
                withAnimation(.easeOut(duration: 0.2)) { showSplash = false }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    store.saveToCache()
                    BackgroundRefreshManager.shared.scheduleNextRefresh()
                    isLocked = true
                case .active:
                    syncEngine?.refresh()
                    unlock()
                default:
                    break
                }
            }
        }
    }

    @State private var isAuthenticating = false

    private func unlock() {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            isLocked = false
            isAuthenticating = false
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "解锁 Mira"
        ) { success, _ in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    withAnimation { isLocked = false }
                }
            }
        }
    }

    private func startServices() {
        guard syncEngine == nil else { return }
        store.loadFromCache()
        let cmd = CommandWriter(config: config, store: store)
        let engine = SyncEngine(config: config, store: store)
        let todos = TodoStore(config: config)
        engine.commands = cmd
        commands = cmd
        todoStore = todos
        syncEngine = engine
        notifications.agentName = config.agentName
        engine.startPolling()
        todos.refresh()
        notifications.onApproval = { itemId, approved in
            cmd.reply(to: itemId, content: approved ? "Approved" : "Rejected")
        }
        BackgroundRefreshManager.shared.configure(config: config, store: store, notifications: notifications)
        BackgroundRefreshManager.shared.scheduleNextRefresh()
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(ItemStore.self) private var store
    @Environment(NotificationManager.self) private var notifications

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .badge(store.needsAttention.count)

            TodoView()
                .tabItem {
                    Label("Todo", systemImage: "checklist")
                }

            HealthView()
                .tabItem {
                    Label("Health", systemImage: "heart.text.clipboard")
                }

            ArtifactsView()
                .tabItem {
                    Label("Artifacts", systemImage: "archivebox")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(Color(hex: 0x00A884))
        .onChange(of: store.items) { _, newItems in
            notifications.processChanges(items: newItems)
        }
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    let agentName: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color(hex: 0x008069).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                               value: pulse)

                Text(agentName)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                ProgressView()
                    .tint(.white)
                    .padding(.top, 8)
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Lock Screen

struct LockScreenView: View {
    let agentName: String
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color(hex: 0x111B21).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "faceid")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(hex: 0x00A884))

                Text(agentName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Button {
                    onUnlock()
                } label: {
                    Text("解锁")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color(hex: 0x00A884), in: Capsule())
                }
            }
        }
    }
}
