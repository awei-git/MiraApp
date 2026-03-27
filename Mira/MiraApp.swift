import SwiftUI
import MiraBridge

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
                case .active:
                    syncEngine?.refresh()
                default:
                    break
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
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(ItemStore.self) private var store

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
