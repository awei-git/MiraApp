import SwiftUI
import MiraBridge
import UniformTypeIdentifiers
import Foundation

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
                        backendSection
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
            NavigationLink {
                ArtifactsView()
            } label: {
                HStack {
                    Text("artifacts")
                        .font(.system(size: 13).monospaced())
                        .foregroundStyle(waAccent)
                        .tracking(0.5)
                    Spacer()
                    Image(systemName: "archivebox")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(waAccent)
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

    private var apiSection: some View {
        sectionGroup("api") {
            kvRow("server", value: (config.serverURL ?? BridgeConfig.defaultServerURL).absoluteString)
            kvRow("write fallback", value: config.apiWriteFallbackToICloud ? "icloud" : "local queue")
            actionRow(config.apiWriteFallbackToICloud ? "use local queue" : "use icloud fallback", color: waAccent) {
                config.apiWriteFallbackToICloud.toggle()
            }
        }
    }

    private var backendSection: some View {
        sectionGroup("backend") {
            NavigationLink {
                BackendDashboardView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ops dashboard")
                            .font(.system(size: 13).monospaced())
                            .foregroundStyle(waAccent)
                            .tracking(0.5)
                        Text("pipelines, usage, memory, model assignments")
                            .font(.system(size: 11))
                            .foregroundStyle(waTextDim)
                    }
                    Spacer()
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(waAccent)
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

// MARK: - Backend Dashboard

private struct BackendDashboardView: View {
    @Environment(BridgeConfig.self) private var config
    @State private var snapshot: BackendDashboardSnapshot?
    @State private var errorText: String?
    @State private var loading = false
    @State private var selectedStep: SelectedBackendStep?
    @State private var usageSort: BackendUsageSort = .cost
    @State private var modelDrafts: [String: String] = [:]
    @State private var budgetDrafts: [String: String] = [:]
    @State private var savingAgent: String?

    var body: some View {
        ZStack {
            waListBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let snapshot {
                        BackendOverview(snapshot: snapshot)
                        BackendDailyUsageChart(history: snapshot.outputs?.jobs?.usageHistory)
                        BackendPipelineSection(pipelines: snapshot.pipelines ?? []) { pipeline, step in
                            selectedStep = SelectedBackendStep(pipeline: pipeline, step: step)
                        }
                        BackendUsageSection(
                            rows: sortedAgentRows(snapshot.outputs?.jobs?.agentStats ?? []),
                            sort: $usageSort
                        )
                        modelAssignmentSection(snapshot)
                        BackendMemorySection(memory: snapshot.memory)
                    } else if loading {
                        ProgressView()
                            .tint(waAccent)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundStyle(waStatusAlert)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(waCardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 90)
            }
            .refreshable { await loadDashboard() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("backend")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(waTextPri)
                    .tracking(0.3)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadDashboard() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .tint(waAccent)
            }
        }
        .task { await loadDashboard() }
        .sheet(item: $selectedStep) { selection in
            BackendStepDetail(selection: selection)
                .presentationDetents([.medium, .large])
        }
    }

    @MainActor
    private func loadDashboard() async {
        loading = true
        errorText = nil
        do {
            let decoded = try await fetchDashboard()
            snapshot = decoded
            seedDrafts(decoded)
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }

    private func fetchDashboard() async throws -> BackendDashboardSnapshot {
        let userId = config.profile?.id ?? "ang"
        let base = config.serverURL ?? BridgeConfig.defaultServerURL
        let url = base.appending(path: "api/\(userId)/backend-dashboard")
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await MiraPinnedURLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BackendDashboardError.badResponse
        }
        return try JSONDecoder().decode(BackendDashboardSnapshot.self, from: data)
    }

    @MainActor
    private func updateModelAssignment(_ assignment: BackendModelAssignment) async {
        let agent = assignment.agent
        let model = modelDrafts[agent] ?? assignment.model
        let budget = Int(budgetDrafts[agent] ?? "") ?? assignment.tokenBudget
        savingAgent = agent
        defer { savingAgent = nil }
        do {
            let userId = config.profile?.id ?? "ang"
            let base = config.serverURL ?? BridgeConfig.defaultServerURL
            let url = base.appending(path: "api/\(userId)/backend-dashboard/models/\(agent)")
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(BackendModelAssignmentPayload(model: model, tokenBudget: budget))
            let (_, response) = try await MiraPinnedURLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw BackendDashboardError.badResponse
            }
            await loadDashboard()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func seedDrafts(_ snapshot: BackendDashboardSnapshot) {
        var models: [String: String] = [:]
        var budgets: [String: String] = [:]
        for row in snapshot.models ?? [] {
            models[row.agent] = row.model
            budgets[row.agent] = "\(row.tokenBudget)"
        }
        modelDrafts = models
        budgetDrafts = budgets
    }

    private func sortedAgentRows(_ rows: [BackendAgentStat]) -> [BackendAgentStat] {
        rows.sorted { lhs, rhs in
            switch usageSort {
            case .cost:
                return lhs.cost30d == rhs.cost30d ? lhs.calls30d > rhs.calls30d : lhs.cost30d > rhs.cost30d
            case .tokens:
                return lhs.tokens30d == rhs.tokens30d ? lhs.cost30d > rhs.cost30d : lhs.tokens30d > rhs.tokens30d
            case .calls:
                return lhs.calls30d == rhs.calls30d ? lhs.cost30d > rhs.cost30d : lhs.calls30d > rhs.calls30d
            case .agent:
                return lhs.agent.localizedCaseInsensitiveCompare(rhs.agent) == .orderedAscending
            }
        }
    }

    @ViewBuilder
    private func modelAssignmentSection(_ snapshot: BackendDashboardSnapshot) -> some View {
        BackendSectionTitle("model assignments")
        VStack(spacing: 0) {
            ForEach(snapshot.models ?? []) { assignment in
                BackendModelAssignmentRow(
                    assignment: assignment,
                    options: snapshot.modelOptions ?? [],
                    modelDrafts: $modelDrafts,
                    budgetDrafts: $budgetDrafts,
                    saving: savingAgent == assignment.agent
                ) {
                    Task { await updateModelAssignment(assignment) }
                }
                if assignment.id != (snapshot.models ?? []).last?.id {
                    Rectangle().fill(waBorder).frame(height: 0.5).padding(.leading, 16)
                }
            }
        }
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(waBorder, lineWidth: 0.7)
        )
        .padding(.horizontal, 16)
    }
}

private struct BackendOverview: View {
    let snapshot: BackendDashboardSnapshot

    var body: some View {
        BackendSectionTitle("status")
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                BackendMetricCard(
                    title: "service",
                    value: snapshot.service?.heartbeat?.status.capitalized ?? "Unknown",
                    detail: snapshot.service?.heartbeat?.timestamp?.prettyTimestamp ?? "no heartbeat",
                    color: backendStatusColor(snapshot.service?.heartbeat?.status)
                )
                BackendMetricCard(
                    title: "pipelines",
                    value: "\(snapshot.pipelines?.count ?? 0)",
                    detail: pipelineStatusSummary(snapshot.pipelines ?? []),
                    color: waAccent
                )
            }
            HStack(spacing: 10) {
                let today = snapshot.outputs?.jobs?.usageHistory?.totals?.today
                BackendMetricCard(
                    title: "today tokens",
                    value: compactTokens(today?.tokens ?? 0),
                    detail: "\(today?.calls ?? 0) calls - \(money(today?.costUsd ?? 0))",
                    color: colorAnalysis
                )
                let month = snapshot.outputs?.jobs?.usageHistory?.totals?.last30d
                BackendMetricCard(
                    title: "30d cost",
                    value: money(month?.costUsd ?? 0),
                    detail: "\(month?.calls ?? 0) calls - \(compactTokens(month?.tokens ?? 0)) tokens",
                    color: colorExplore
                )
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct BackendMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold).monospaced())
                    .foregroundStyle(waTextDim)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(waTextSec)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.55), lineWidth: 0.8)
        )
    }
}

private struct BackendDailyUsageChart: View {
    let history: BackendUsageHistory?

    var rows: [BackendDailyUsage] {
        Array((history?.daily ?? []).suffix(30))
    }

    var maxTokens: Int {
        max(1, rows.map(\.tokens).max() ?? 1)
    }

    var presentFamilies: [String] {
        let families = Set(rows.flatMap { $0.models.keys.map(modelFamily) })
        let preferred = ["Claude", "DeepSeek", "Local", "OpenAI", "Gemini", "Other"]
        return preferred.filter { families.contains($0) }
    }

    var body: some View {
        BackendSectionTitle("30d daily tokens")
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ForEach(presentFamilies, id: \.self) { family in
                    HStack(spacing: 5) {
                        Circle().fill(modelFamilyColor(family)).frame(width: 7, height: 7)
                        Text(family)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(waTextSec)
                    }
                }
            }
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(rows) { row in
                        let spacingWidth = CGFloat(max(rows.count - 1, 0)) * 3
                        let barWidth = max(5, (proxy.size.width - spacingWidth) / CGFloat(max(rows.count, 1)))
                        let barHeight = max(4, CGFloat(row.tokens) / CGFloat(maxTokens) * proxy.size.height)
                        let accessibilityText = "\(row.date), \(row.tokens) tokens"
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(modelFamilyColor(row.dominantModelFamily))
                            .frame(width: barWidth, height: barHeight)
                            .accessibilityLabel(accessibilityText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: 68)
            HStack {
                Text(rows.first?.date.dropFirst(5) ?? "")
                Spacer()
                Text(rows.last?.date.dropFirst(5) ?? "")
            }
            .font(.system(size: 10).monospaced())
            .foregroundStyle(waTextDim)
        }
        .padding(14)
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(waBorder, lineWidth: 0.7)
        )
        .padding(.horizontal, 16)
    }
}

private struct BackendPipelineSection: View {
    let pipelines: [BackendPipeline]
    let select: (BackendPipeline, BackendPipelineStep) -> Void

    var body: some View {
        BackendSectionTitle("pipelines")
        VStack(alignment: .leading, spacing: 10) {
            BackendStatusLegend()
            ForEach(pipelines) { pipeline in
                BackendPipelineRow(pipeline: pipeline, select: select)
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct BackendStatusLegend: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                legend("success", "green")
                legend("scheduled / queued", "blue")
                legend("running / attention", "yellow")
                legend("failed", "red")
                legend("not observed", "gray")
            }
            .padding(.vertical, 2)
        }
    }

    private func legend(_ label: String, _ status: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(backendStatusColor(status)).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10).monospaced())
                .foregroundStyle(waTextSec)
        }
    }
}

private struct BackendPipelineRow: View {
    let pipeline: BackendPipeline
    let select: (BackendPipeline, BackendPipelineStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pipeline.name)
                        .font(.system(size: 14, weight: .semibold).monospaced())
                        .foregroundStyle(waTextPri)
                    Text(pipeline.trigger ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(waTextSec)
                        .lineLimit(2)
                    Text("last success: \((pipeline.lastSuccessAt ?? "").prettyTimestamp)")
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(waTextDim)
                }
                Spacer(minLength: 8)
                Text(statusLabel(pipeline.status))
                    .font(.system(size: 11, weight: .semibold).monospaced())
                    .foregroundStyle(backendStatusColor(pipeline.status))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(backendStatusColor(pipeline.status).opacity(0.16), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array((pipeline.steps ?? []).enumerated()), id: \.element.id) { idx, step in
                        Button {
                            select(pipeline, step)
                        } label: {
                            Circle()
                                .fill(backendStatusColor(step.status).opacity(0.18))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(backendStatusColor(step.status), lineWidth: 2))
                                .overlay {
                                    if step.status == "green" {
                                        Circle().fill(backendStatusColor(step.status)).frame(width: 6, height: 6)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        if idx < (pipeline.steps?.count ?? 0) - 1 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(waTextDim)
                                .frame(width: 28)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if let detail = pipeline.statusDetail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(waTextSec)
                    .lineLimit(3)
            }
            if let output = pipeline.outputs?.first {
                Text("latest output: \(output.title) - \((output.updatedAt ?? "").prettyTimestamp)")
                    .font(.system(size: 11))
                    .foregroundStyle(waAccent)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(backendStatusColor(pipeline.status).opacity(0.42), lineWidth: 0.8)
        )
    }
}

private struct BackendUsageSection: View {
    let rows: [BackendAgentStat]
    @Binding var sort: BackendUsageSort

    var body: some View {
        BackendSectionTitle("agent usage")
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(BackendUsageSort.allCases, id: \.self) { option in
                    Button {
                        sort = option
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 11, weight: .semibold).monospaced())
                            .foregroundStyle(sort == option ? waListBg : waTextSec)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(sort == option ? waAccent : waCardHi, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    usageHeader
                    ForEach(rows.prefix(30)) { row in
                        HStack(spacing: 10) {
                            Text(row.agent).frame(width: 132, alignment: .leading)
                            Text("\(row.calls30d)").frame(width: 58, alignment: .trailing)
                            Text(compactTokens(row.tokens30d)).frame(width: 76, alignment: .trailing)
                            Text(money(row.cost30d)).frame(width: 72, alignment: .trailing)
                            Text(row.topModel).frame(width: 150, alignment: .leading)
                        }
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(waTextSec)
                        .padding(.vertical, 8)
                        Rectangle().fill(waBorder).frame(height: 0.5)
                    }
                }
            }
        }
        .padding(14)
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(waBorder, lineWidth: 0.7)
        )
        .padding(.horizontal, 16)
    }

    private var usageHeader: some View {
        HStack(spacing: 10) {
            Text("agent").frame(width: 132, alignment: .leading)
            Text("calls").frame(width: 58, alignment: .trailing)
            Text("tokens").frame(width: 76, alignment: .trailing)
            Text("cost").frame(width: 72, alignment: .trailing)
            Text("top model").frame(width: 150, alignment: .leading)
        }
        .font(.system(size: 10, weight: .semibold).monospaced())
        .foregroundStyle(waTextDim)
        .padding(.bottom, 7)
    }
}

private struct BackendModelAssignmentRow: View {
    let assignment: BackendModelAssignment
    let options: [String]
    @Binding var modelDrafts: [String: String]
    @Binding var budgetDrafts: [String: String]
    let saving: Bool
    let save: () -> Void

    var modelOptions: [String] {
        var values = options
        if !assignment.model.isEmpty, !values.contains(assignment.model) {
            values.insert(assignment.model, at: 0)
        }
        return values
    }

    var budget: Int {
        Int(budgetDrafts[assignment.agent] ?? "") ?? assignment.tokenBudget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(assignment.agent)
                    .font(.system(size: 12, weight: .semibold).monospaced())
                    .foregroundStyle(waTextPri)
                Spacer()
                if assignment.override == true {
                    Text("override")
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(colorAnalysis)
                }
                if saving {
                    ProgressView().scaleEffect(0.65).tint(waAccent)
                }
            }
            HStack(spacing: 8) {
                Picker("model", selection: Binding(
                    get: { modelDrafts[assignment.agent] ?? assignment.model },
                    set: { modelDrafts[assignment.agent] = $0 }
                )) {
                    ForEach(modelOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(waAccent)
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField("budget", text: Binding(
                    get: { budgetDrafts[assignment.agent] ?? "\(assignment.tokenBudget)" },
                    set: { budgetDrafts[assignment.agent] = $0.filter(\.isNumber) }
                ))
                .keyboardType(.numberPad)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(budget < 16000 ? waStatusWarn : waTextPri)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(waCardHi, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Button(action: save) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(waListBg)
                        .frame(width: 30, height: 30)
                        .background(waAccent, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if budget < 16000 {
                Text("token budget looks low")
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(waStatusWarn)
            }
        }
        .padding(14)
    }
}

private struct BackendMemorySection: View {
    let memory: BackendMemory?

    var body: some View {
        BackendSectionTitle("memory window")
        VStack(alignment: .leading, spacing: 13) {
            Text(memory?.kernel?.identity ?? "No kernel identity recorded.")
                .font(.system(size: 13))
                .foregroundStyle(waTextPri)
                .lineSpacing(2)

            HStack(spacing: 10) {
                memoryPill("ledger", "\(memory?.status?.counts?.ledger ?? 0)")
                memoryPill("commits", "\(memory?.status?.counts?.commits ?? 0)")
                memoryPill("queued", "\(memory?.status?.counts?.queued ?? 0)")
            }

            if let summary = latestCommitSummary {
                Text("summary: \(summary)")
                    .font(.system(size: 12))
                    .foregroundStyle(waTextSec)
                    .lineLimit(3)
            }

            scrollBlock(title: "failure lessons", rows: (memory?.kernel?.failureLessons ?? []).map {
                "\(($0.date ?? "").prettyTimestamp) - \($0.incident)"
            })
            scrollBlock(title: "recent commits", rows: (memory?.commits ?? []).suffix(12).reversed().map {
                "\(($0.timestamp ?? "").prettyTimestamp) - \($0.pipeline ?? "") - \($0.summary ?? $0.status ?? "")"
            })
        }
        .padding(14)
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(waBorder, lineWidth: 0.7)
        )
        .padding(.horizontal, 16)
    }

    private var latestCommitSummary: String? {
        memory?.commits?.last?.summary
    }

    private func memoryPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10).monospaced())
                .foregroundStyle(waTextDim)
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(waTextPri)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(waCardHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func scrollBlock(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold).monospaced())
                .foregroundStyle(waTextDim)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Text(row)
                            .font(.system(size: 11))
                            .foregroundStyle(waTextSec)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 150)
            .background(waCardHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct BackendStepDetail: View {
    let selection: SelectedBackendStep

    var body: some View {
        NavigationStack {
            ZStack {
                waListBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        BackendDetailRow("pipeline", selection.pipeline.name)
                        BackendDetailRow("step", selection.step.name)
                        BackendDetailRow("status", statusLabel(selection.step.status), color: backendStatusColor(selection.step.status))
                        BackendDetailRow("model", modelText(selection.step))
                        BackendDetailRow("model source", selection.step.modelSource ?? "not recorded")
                        BackendDetailRow("tokens", "\(selection.step.tokens ?? 0)")
                        BackendDetailRow("cost", money(selection.step.costUsd ?? 0))
                        BackendDetailRow("timestamp", (selection.step.observedAt ?? "").prettyTimestamp)
                        if let error = selection.step.error, !error.isEmpty {
                            BackendDetailRow("error", error, color: waStatusAlert)
                        }
                        if let outputs = selection.pipeline.outputs, !outputs.isEmpty {
                            Text("outputs")
                                .font(.system(size: 10, weight: .semibold).monospaced())
                                .foregroundStyle(waTextDim)
                            ForEach(outputs) { output in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(output.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(waTextPri)
                                    Text("\(output.status ?? "ready") - \((output.updatedAt ?? "").prettyTimestamp)")
                                        .font(.system(size: 11).monospaced())
                                        .foregroundStyle(waTextSec)
                                    if let error = output.error, !error.isEmpty {
                                        Text(error)
                                            .font(.system(size: 11))
                                            .foregroundStyle(waStatusAlert)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(waCardHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("step detail")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func modelText(_ step: BackendPipelineStep) -> String {
        if let model = step.model, !model.isEmpty {
            return step.modelRecorded == true ? model : "\(model) (configured)"
        }
        if let configured = step.configuredModel, !configured.isEmpty {
            return "\(configured) (configured)"
        }
        return "not recorded"
    }
}

private struct BackendDetailRow: View {
    let key: String
    let value: String
    let color: Color?

    init(_ key: String, _ value: String, color: Color? = nil) {
        self.key = key
        self.value = value.isEmpty ? "not recorded" : value
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key.uppercased())
                .font(.system(size: 10, weight: .semibold).monospaced())
                .foregroundStyle(waTextDim)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(color ?? waTextPri)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct BackendSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold).monospaced())
            .foregroundStyle(waTextDim)
            .tracking(1.1)
            .padding(.horizontal, 18)
    }
}

private struct SelectedBackendStep: Identifiable {
    let pipeline: BackendPipeline
    let step: BackendPipelineStep
    var id: String { "\(pipeline.name)-\(step.name)" }
}

private enum BackendUsageSort: String, CaseIterable {
    case cost
    case tokens
    case calls
    case agent
}

private enum BackendDashboardError: LocalizedError {
    case badResponse

    var errorDescription: String? {
        "Mira backend dashboard API returned an invalid response."
    }
}

// MARK: - Backend API Models

private struct BackendDashboardSnapshot: Codable {
    let serverTime: String?
    let service: BackendService?
    let memory: BackendMemory?
    let pipelines: [BackendPipeline]?
    let models: [BackendModelAssignment]?
    let modelOptions: [String]?
    let outputs: BackendOutputs?

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case service, memory, pipelines, models, outputs
        case modelOptions = "model_options"
    }
}

private struct BackendService: Codable {
    let heartbeat: BackendHeartbeat?
}

private struct BackendHeartbeat: Codable {
    let timestamp: String?
    let status: String
    let busy: Bool?
    let activeCount: Int?

    enum CodingKeys: String, CodingKey {
        case timestamp, status, busy
        case activeCount = "active_count"
    }
}

private struct BackendMemory: Codable {
    let status: BackendMemoryStatus?
    let kernel: BackendKernel?
    let commits: [BackendCommit]?
}

private struct BackendMemoryStatus: Codable {
    let overall: String?
    let counts: BackendMemoryCounts?
}

private struct BackendMemoryCounts: Codable {
    let ledger: Int?
    let commits: Int?
    let effects: Int?
    let queued: Int?
    let items: Int?
}

private struct BackendKernel: Codable {
    let identity: String?
    let failureLessons: [BackendFailureLesson]?

    enum CodingKeys: String, CodingKey {
        case identity
        case failureLessons = "failure_lessons"
    }
}

private struct BackendFailureLesson: Codable, Identifiable {
    let id: String
    let incident: String
    let rootCause: String?
    let behavioralChange: String?
    let date: String?

    enum CodingKeys: String, CodingKey {
        case id, incident, date
        case rootCause = "root_cause"
        case behavioralChange = "behavioral_change"
    }
}

private struct BackendCommit: Codable, Identifiable {
    let id: String
    let pipeline: String?
    let status: String?
    let summary: String?
    let timestamp: String?
}

private struct BackendPipeline: Codable, Identifiable {
    let name: String
    let status: String?
    let statusText: String?
    let statusDetail: String?
    let trigger: String?
    let lastRun: String?
    let lastSuccessAt: String?
    let lastSuccessOutcome: String?
    let outcome: String?
    let error: String?
    let usage: BackendUsageBucket?
    let configuredAgent: String?
    let configuredModel: String?
    let outputs: [BackendPipelineOutput]?
    let steps: [BackendPipelineStep]?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, status, trigger, outcome, error, usage, outputs, steps
        case statusText = "status_text"
        case statusDetail = "status_detail"
        case lastRun = "last_run"
        case lastSuccessAt = "last_success_at"
        case lastSuccessOutcome = "last_success_outcome"
        case configuredAgent = "configured_agent"
        case configuredModel = "configured_model"
    }
}

private struct BackendPipelineStep: Codable, Identifiable {
    let name: String
    let type: String?
    let status: String?
    let model: String?
    let modelRecorded: Bool?
    let modelSource: String?
    let configuredModel: String?
    let configuredAgent: String?
    let usageRecorded: Bool?
    let costUsd: Double?
    let tokens: Int?
    let observedAt: String?
    let timestampSource: String?
    let error: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, type, status, model, tokens, error
        case modelRecorded = "model_recorded"
        case modelSource = "model_source"
        case configuredModel = "configured_model"
        case configuredAgent = "configured_agent"
        case usageRecorded = "usage_recorded"
        case costUsd = "cost_usd"
        case observedAt = "observed_at"
        case timestampSource = "timestamp_source"
    }
}

private struct BackendPipelineOutput: Codable, Identifiable {
    let title: String
    let status: String?
    let updatedAt: String?
    let href: String?
    let error: String?

    var id: String { "\(title)-\(updatedAt ?? "")" }

    enum CodingKeys: String, CodingKey {
        case title, status, href, error
        case updatedAt = "updated_at"
    }
}

private struct BackendOutputs: Codable {
    let jobs: BackendJobs?
}

private struct BackendJobs: Codable {
    let usageHistory: BackendUsageHistory?
    let agentStats: [BackendAgentStat]?

    enum CodingKeys: String, CodingKey {
        case usageHistory = "usage_history"
        case agentStats = "agent_stats"
    }
}

private struct BackendUsageHistory: Codable {
    let days: Int?
    let daily: [BackendDailyUsage]?
    let totals: BackendUsageTotals?
}

private struct BackendUsageTotals: Codable {
    let today: BackendUsageBucket?
    let last7d: BackendUsageBucket?
    let last30d: BackendUsageBucket?

    enum CodingKeys: String, CodingKey {
        case today
        case last7d = "last_7d"
        case last30d = "last_30d"
    }
}

private struct BackendUsageBucket: Codable {
    let calls: Int?
    let tokens: Int?
    let costUsd: Double?
    let models: [String: BackendUsageLeaf]?
    let agents: [String: BackendUsageLeaf]?

    enum CodingKeys: String, CodingKey {
        case calls, tokens, models, agents
        case costUsd = "cost_usd"
    }
}

private struct BackendUsageLeaf: Codable {
    let calls: Int?
    let tokens: Int?
    let costUsd: Double?

    enum CodingKeys: String, CodingKey {
        case calls, tokens
        case costUsd = "cost_usd"
    }
}

private struct BackendDailyUsage: Codable, Identifiable {
    let date: String
    let calls: Int
    let tokens: Int
    let costUsd: Double
    let models: [String: BackendUsageLeaf]
    let agents: [String: BackendUsageLeaf]

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, calls, tokens, models, agents
        case costUsd = "cost_usd"
    }

    var dominantModelFamily: String {
        let topModel = models.max { lhs, rhs in
            (lhs.value.tokens ?? 0) < (rhs.value.tokens ?? 0)
        }?.key ?? ""
        return modelFamily(topModel)
    }
}

private struct BackendAgentStat: Codable, Identifiable {
    let agent: String
    let calls30d: Int
    let tokens30d: Int
    let cost30d: Double
    let dailyAvg: Double?
    let weeklyAvg: Double?
    let monthlyAvg: Double?
    let topModel: String

    var id: String { agent }

    enum CodingKeys: String, CodingKey {
        case agent
        case calls30d = "calls_30d"
        case tokens30d = "tokens_30d"
        case cost30d = "cost_30d"
        case dailyAvg = "daily_avg"
        case weeklyAvg = "weekly_avg"
        case monthlyAvg = "monthly_avg"
        case topModel = "top_model"
    }
}

private struct BackendModelAssignment: Codable, Identifiable {
    let agent: String
    let model: String
    let tokenBudget: Int
    let override: Bool?

    var id: String { agent }

    enum CodingKeys: String, CodingKey {
        case agent, model, override
        case tokenBudget = "token_budget"
    }
}

private struct BackendModelAssignmentPayload: Encodable {
    let model: String
    let tokenBudget: Int

    enum CodingKeys: String, CodingKey {
        case model
        case tokenBudget = "token_budget"
    }
}

// MARK: - Backend Formatting

private func backendStatusColor(_ status: String?) -> Color {
    switch (status ?? "").lowercased() {
    case "green", "online", "success", "done", "completed":
        return Color(hex: 0x4DFF9A)
    case "blue", "scheduled", "queued", "pending":
        return Color(hex: 0xB79CFF)
    case "yellow", "running", "attention", "active":
        return waStatusWarn
    case "red", "failed", "error":
        return waStatusAlert
    default:
        return Color(hex: 0xA6A29A)
    }
}

private func statusLabel(_ status: String?) -> String {
    switch (status ?? "").lowercased() {
    case "green": return "success"
    case "blue": return "scheduled"
    case "yellow": return "running / attention"
    case "red": return "failed"
    case "gray": return "not observed"
    default: return status ?? "unknown"
    }
}

private func pipelineStatusSummary(_ pipelines: [BackendPipeline]) -> String {
    let green = pipelines.filter { ($0.status ?? "") == "green" }.count
    let blue = pipelines.filter { ($0.status ?? "") == "blue" }.count
    let yellow = pipelines.filter { ($0.status ?? "") == "yellow" }.count
    let red = pipelines.filter { ($0.status ?? "") == "red" }.count
    return "\(green) success - \(blue) scheduled - \(yellow) attention - \(red) failed"
}

private func compactTokens(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

private func money(_ value: Double) -> String {
    if value >= 100 {
        return String(format: "$%.0f", value)
    }
    return String(format: "$%.2f", value)
}

private func modelFamily(_ model: String) -> String {
    let value = model.lowercased()
    if value.contains("claude") { return "Claude" }
    if value.contains("deepseek") { return "DeepSeek" }
    if value.contains("gemma") || value.contains("omlx") || value.contains("local") { return "Local" }
    if value.contains("gpt") || value.contains("openai") { return "OpenAI" }
    if value.contains("gemini") { return "Gemini" }
    return "Other"
}

private func modelFamilyColor(_ family: String) -> Color {
    switch family {
    case "Claude": return colorCode
    case "DeepSeek": return colorAnalysis
    case "Local": return colorWriting
    case "OpenAI": return colorExplore
    case "Gemini": return colorJournal
    default: return Color(hex: 0xA6A29A)
    }
}

private extension String {
    var prettyTimestamp: String {
        guard !isEmpty else { return "not observed" }
        var value = replacingOccurrences(of: "Z", with: "")
        if let plus = value.firstIndex(of: "+") {
            value = String(value[..<plus])
        }
        value = value.replacingOccurrences(of: "T", with: " ")
        if value.count >= 16 {
            return String(value.prefix(16))
        }
        return value
    }
}
