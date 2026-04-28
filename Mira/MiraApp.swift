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
    @State private var healthData = HealthDataProvider()
    @State private var showSplash = true
    @State private var isLocked = false

    init() {
        BackgroundRefreshManager.shared.registerTask()
        configureAppearance()
    }

    /// Apply the Mira palette to UIKit-backed chrome (nav bar + tab bar)
    /// so SwiftUI's NavigationStack/TabView don't fall back to default white/blur.
    private func configureAppearance() {
        let listBg = UIColor(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x22/255.0, alpha: 1)
        let textPri = UIColor(red: 0xF2/255.0, green: 0xF2/255.0, blue: 0xEE/255.0, alpha: 1)
        let textDim = UIColor(red: 0x6E/255.0, green: 0x6E/255.0, blue: 0x7A/255.0, alpha: 1)
        let accent  = UIColor(red: 0x8F/255.0, green: 0xE5/255.0, blue: 0xB8/255.0, alpha: 1)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = listBg
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: textPri]
        nav.largeTitleTextAttributes = [.foregroundColor: textPri]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = accent

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = listBg
        tab.shadowColor = .clear
        let item = tab.stackedLayoutAppearance
        item.normal.iconColor = textDim
        item.normal.titleTextAttributes = [.foregroundColor: textDim]
        item.selected.iconColor = accent
        item.selected.titleTextAttributes = [.foregroundColor: accent]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                waListBg.ignoresSafeArea()

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
                        .environment(healthData)
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
                case .active:
                    syncEngine?.startPolling()  // reset fast-poll to get fresh heartbeat
                    if config.isSetup && config.isProfileSelected {
                        healthData.refresh(config: config)  // warm Health tab before user taps it
                    }
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
        // deviceOwnerAuthentication = biometrics OR passcode fallback,
        // so we always have a way in even if Face ID misfires.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            isAuthenticating = false
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
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

        // Warm health data immediately so the Health tab is ready when first opened.
        healthData.refresh(config: config)
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
        .tint(waAccent)
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
            waListBg.ignoresSafeArea()

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
            waListBg.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "faceid")
                    .font(.system(size: 56))
                    .foregroundStyle(waAccent)

                Text(agentName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(waTextPri)

                Button {
                    onUnlock()
                } label: {
                    Text("unlock")
                        .font(.system(size: 13).monospaced())
                        .foregroundStyle(waListBg)
                        .tracking(0.5)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 11)
                        .background(waAccent, in: Capsule())
                }
            }
        }
        // Auto-trigger Face ID / passcode prompt when the lock screen appears,
        // not just on scenePhase changes (which can miss programmatic launches).
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onUnlock()
            }
        }
    }
}
