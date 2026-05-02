import SwiftUI
import MiraBridge
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(BridgeConfig.self) private var config
    @Environment(SyncEngine.self) private var sync
    @Environment(ItemStore.self) private var store
    @State private var showFolderPicker = false

    private static let heartbeatFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                waListBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        agentSection
                        dataSection
                        apiSection
                        profileSection
                        workspaceSection
                        if let error = config.error { errorSection(error) }
                        debugSection
                        Spacer(minLength: 80)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("settings")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(waTextPri)
                        .tracking(0.3)
                }
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    config.setFolder(url)
                }
            }
        }
    }

    // MARK: - Sections

    private var agentSection: some View {
        sectionGroup("agent") {
            kvRow("status",
                  trailing: HStack(spacing: 8) {
                      Circle()
                          .fill(sync.agentOnline ? waStatusGood : waStatusAlert)
                          .frame(width: 7, height: 7)
                      Text(sync.agentOnline ? "online" : "offline")
                          .font(.system(size: 13).monospaced())
                          .foregroundStyle(sync.agentOnline ? waStatusGood : waStatusAlert)
                  })
            if let hb = sync.heartbeat {
                kvRow("heartbeat", value: Self.heartbeatFormatter.string(from: hb.date))
                if hb.isBusy {
                    kvRow("active tasks", value: "\(hb.activeCount ?? 0)")
                }
            }
            if !sync.heartbeatDebug.isEmpty {
                Text(sync.heartbeatDebug)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(waCardBg)
            }
        }
    }

    private var dataSection: some View {
        sectionGroup("data") {
            kvRow("items", value: "\(store.items.count)")
            kvRow("active", value: "\(store.activeRequests.count)")
            kvRow("discussions", value: "\(store.discussions.count)")
            kvRow("feeds", value: "\(store.feeds.count)")
        }
    }

    private var apiSection: some View {
        sectionGroup("api") {
            kvRow("server", value: (config.serverURL ?? BridgeConfig.defaultServerURL).absoluteString)
            kvRow("write fallback", value: config.apiWriteFallbackToICloud ? "icloud" : "local queue")
            actionRow(config.apiWriteFallbackToICloud ? "use local queue" : "use icloud fallback", color: waAccent) {
                config.apiWriteFallbackToICloud.toggle()
            }
        }
    }

    private var profileSection: some View {
        sectionGroup("profile") {
            if let p = config.profile {
                kvRow("user", value: p.displayName)
                kvRow("agent", value: p.agentName)
            }
            actionRow("switch profile", color: waAccent) {
                config.profile = nil
                UserDefaults.standard.removeObject(forKey: "selected_profile")
            }
        }
    }

    private var workspaceSection: some View {
        sectionGroup("workspace") {
            if let url = config.bridgeURL {
                Text(url.path())
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(waCardBg)
            }
            actionRow("change workspace", color: waAccent) {
                showFolderPicker = true
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
        sectionGroup("error") {
            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(waStatusAlert)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(waCardBg)
        }
    }

    private var debugSection: some View {
        sectionGroup("debug log") {
            Text(sync.debugLog.isEmpty ? "no log yet" : sync.debugLog)
                .font(.system(size: 11).monospaced())
                .foregroundStyle(waTextSec)
                .lineSpacing(2)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(waCardBg)
        }
    }

    // MARK: - Section primitives

    @ViewBuilder
    private func sectionGroup<Content: View>(
        _ title: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11).monospaced())
                .foregroundStyle(waTextDim)
                .tracking(1.2)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                content()
            }
        }
    }

    private func kvRow<Trailing: View>(
        _ key: String,
        trailing: Trailing
    ) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 13).monospaced())
                .foregroundStyle(waTextSec)
                .tracking(0.5)
            Spacer()
            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(waCardBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(waBorder).frame(height: 0.5).padding(.leading, 18)
        }
    }

    private func kvRow(_ key: String, value: String) -> some View {
        kvRow(key, trailing:
            Text(value)
                .font(.system(size: 13, weight: .regular).monospaced())
                .foregroundStyle(waTextPri)
        )
    }

    private func actionRow(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 13).monospaced())
                    .foregroundStyle(color)
                    .tracking(0.5)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(waTextDim)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(waCardBg)
        }
        .buttonStyle(.plain)
    }
}
