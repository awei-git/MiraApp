import SwiftUI
import MiraBridge

// Mira palette — soft warm dark with bright pastel accents.
let waListBg    = Color(hex: 0x1A1A22) // warm soft dark — not aggressive black
let waCardBg    = Color(hex: 0x26262F) // surface — clearly lifted from bg
let waCardHi    = Color(hex: 0x32323D) // surface elevated (insights / alerts)
let waChatBg    = Color(hex: 0x14141B) // chat bg — one notch darker than list
let waBorder    = Color(hex: 0x3A3A46) // hairline separator
let waTextPri   = Color(hex: 0xF2F2EE) // warm white
let waTextSec   = Color(hex: 0xA0A0AC) // soft cool gray
let waTextDim   = Color(hex: 0x6E6E7A) // dimmed (timestamps, labels)

// Single accent — bright mint. Used for the FAB, active tab, focus only.
let waAccent    = Color(hex: 0x8FE5B8)
let waOutBubble = Color(hex: 0x2C4438) // outgoing bubble — deep mint shadow
let waInBubble  = Color(hex: 0x1C1C20) // incoming bubble — surface
let waLink      = Color(hex: 0xA8EBC8) // links — mint tint

// Status — bright + cheerful. Coral for alerts, honey for warnings.
let waStatusAlert = Color(hex: 0xFF9081) // coral — alerts / errors
let waStatusWarn  = Color(hex: 0xFFCB6E) // honey — warnings
let waStatusGood  = Color(hex: 0x8FE5B8) // mint — success / confirmation

// Category palette — a bright, cheerful family. All colors sit at roughly
// the same lightness (~76%) and chroma (~52). Distinct hues, equal visual
// weight, alive in dark mode without being neon.
let colorHealth    = Color(hex: 0xFF9081) // bright coral
let colorAlert     = Color(hex: 0xFFA85C) // sunset orange
let colorSocial    = Color(hex: 0x7FC4F0) // sky blue
let colorWriting   = Color(hex: 0x8FE5B8) // fresh mint
let colorAnalysis  = Color(hex: 0xFFCB6E) // golden honey
let colorJournal   = Color(hex: 0xC7A8F0) // bright lilac
let colorExplore   = Color(hex: 0x7DD8E0) // cyan
let colorPodcast   = Color(hex: 0xFF9DBE) // rose
let colorPhoto     = Color(hex: 0xFFB088) // peach
let colorCode      = Color(hex: 0xA8B8FF) // periwinkle
let colorAgent     = Color(hex: 0xF0D9A8) // warm cream
let colorRequest   = Color(hex: 0xA0C8F0) // sky-slate
let colorDiscuss   = Color(hex: 0xD4A0F0) // orchid

private struct CategoryStyle {
    let label: String
    let color: Color
    let icon: String
}

private func categoryStyle(for item: MiraItem) -> CategoryStyle {
    let tags = Set(item.tags)
    if !tags.isDisjoint(with: ["alert", "error", "crash"]) {
        return .init(label: "alert", color: colorAlert, icon: "exclamationmark.triangle.fill")
    }
    if !tags.isDisjoint(with: ["symptom", "checkup"]) {
        return .init(label: "health", color: colorHealth, icon: "stethoscope")
    }
    if !tags.isDisjoint(with: ["health", "insight"]) {
        return .init(label: "health", color: colorHealth, icon: "heart")
    }
    if !tags.isDisjoint(with: ["podcast", "audio", "tts"]) {
        return .init(label: "podcast", color: colorPodcast, icon: "waveform")
    }
    if !tags.isDisjoint(with: ["writing", "essay", "draft", "article"]) {
        return .init(label: "writing", color: colorWriting, icon: "doc.text")
    }
    if !tags.isDisjoint(with: ["substack", "twitter", "bluesky", "growth", "social"]) {
        return .init(label: "social", color: colorSocial, icon: "bubble.left")
    }
    if !tags.isDisjoint(with: ["journal", "reflect", "spark"]) {
        return .init(label: "journal", color: colorJournal, icon: "moon.stars")
    }
    if !tags.isDisjoint(with: ["explore", "briefing", "news", "feed"]) {
        return .init(label: "explore", color: colorExplore, icon: "globe")
    }
    if !tags.isDisjoint(with: ["analysis", "market", "research", "tetra"]) {
        return .init(label: "analysis", color: colorAnalysis, icon: "chart.line.uptrend.xyaxis")
    }
    if !tags.isDisjoint(with: ["photo", "image", "video"]) {
        return .init(label: "photo", color: colorPhoto, icon: "photo")
    }
    if !tags.isDisjoint(with: ["code", "pipeline", "infra", "agent-task"]) {
        return .init(label: "code", color: colorCode, icon: "chevron.left.forwardslash.chevron.right")
    }
    switch item.type {
    case .request:    return .init(label: "task",    color: colorRequest, icon: "arrow.up.circle")
    case .discussion: return .init(label: "thread",  color: colorDiscuss, icon: "bubble.left.and.bubble.right")
    case .feed:       return .init(label: "agent",   color: colorAgent,   icon: "doc.text")
    }
}

// Convenience
private let accentGreen = waAccent
private let warmBg = waListBg
private let cardBg = waCardBg

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

struct HomeView: View {
    @Environment(BridgeConfig.self) private var config
    @Environment(SyncEngine.self) private var sync
    @Environment(ItemStore.self) private var store
    @Environment(CommandWriter.self) private var commands
    @Environment(NotificationManager.self) private var notifications
    @State private var navigationPath = NavigationPath()
    @State private var showNewItem = false
    @State private var showRecall = false
    @State private var recallQuery = ""
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var expandedSections: Set<String> = ["Today", "Yesterday"]
    @State private var cachedGroupedItems: [(key: String, items: [MiraItem])] = []
    @State private var lastFilteredSignature: [String] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottomTrailing) {
                warmBg.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Search bar
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundStyle(waTextDim)
                            TextField("search", text: $searchText)
                                .font(.system(size: 14))
                                .foregroundStyle(waTextPri)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                        // Needs attention banner
                        if !store.needsAttention.isEmpty {
                            LazyVStack(spacing: 0) {
                                ForEach(store.needsAttention) { item in
                                    NavigationLink(value: item.id) {
                                        AttentionBanner(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 8)
                        }

                        // Date-grouped items
                        ForEach(cachedGroupedItems, id: \.key) { group in
                            let isRecent = group.key == "Today" || group.key == "Yesterday"

                            // Date separator
                            dateSeparator(group.key, count: group.items.count, expanded: isRecent || expandedSections.contains(group.key)) {
                                if !isRecent {
                                    withAnimation {
                                        if expandedSections.contains(group.key) {
                                            expandedSections.remove(group.key)
                                        } else {
                                            expandedSections.insert(group.key)
                                        }
                                    }
                                }
                            }

                            if isRecent || expandedSections.contains(group.key) {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                                        NavigationLink(value: item.id) {
                                            ChatListRow(item: item)
                                        }
                                        .buttonStyle(.plain)
                                        if idx < group.items.count - 1 {
                                            Divider()
                                                .frame(height: 0.5)
                                                .background(waBorder)
                                                .padding(.leading, 18)
                                        }
                                    }
                                }
                                .padding(.bottom, 18)
                            }
                        }

                        Spacer(minLength: 80)
                    }
                }

                // FAB — single accent, restrained
                Button { showNewItem = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(waListBg)
                        .frame(width: 52, height: 52)
                        .background(waAccent)
                        .clipShape(Circle())
                }
                .padding(.trailing, 18)
                .padding(.bottom, 14)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        statusPill
                        Text(config.agentName.lowercased())
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(waTextPri)
                            .tracking(0.3)
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                ItemDetailView(itemId: id)
            }
            .sheet(isPresented: $showNewItem) {
                NewItemSheet()
            }
            .refreshable { sync.refresh() }
            .task(id: searchText) {
                // 300ms debounce for search input
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                debouncedSearchText = searchText
            }
            .onChange(of: debouncedSearchText) { _, _ in recomputeGroupedItems() }
            .onChange(of: store.items) { _, _ in recomputeGroupedItems() }
            .onChange(of: notifications.pendingDeepLinkItemId) { _, itemId in
                guard let itemId else { return }
                notifications.pendingDeepLinkItemId = nil
                navigationPath.append(itemId)
            }
            .onAppear { recomputeGroupedItems() }
        }
    }

    // MARK: - Cache Recomputation

    private func recomputeGroupedItems() {
        let items = filteredItems
        let signature = items.map { "\($0.id)|\($0.updatedAt)|\($0.status.rawValue)|\($0.pinned)" }
        guard signature != lastFilteredSignature else { return }
        lastFilteredSignature = signature
        cachedGroupedItems = Self.computeGroupedItems(from: items)
    }

    private static let groupDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df
    }()

    private static func computeGroupedItems(from filtered: [MiraItem]) -> [(key: String, items: [MiraItem])] {
        let cal = Calendar.current
        var groups: [String: [MiraItem]] = [:]

        for item in filtered {
            let key: String
            if cal.isDateInToday(item.createdDate) {
                key = "Today"
            } else if cal.isDateInYesterday(item.createdDate) {
                key = "Yesterday"
            } else {
                key = groupDateFormatter.string(from: item.createdDate)
            }
            groups[key, default: []].append(item)
        }

        let order = ["Today", "Yesterday"]
        return groups
            .sorted { a, b in
                let ai = order.firstIndex(of: a.key) ?? 99
                let bi = order.firstIndex(of: b.key) ?? 99
                if ai != bi { return ai < bi }
                let ad = a.value.first?.date ?? .distantPast
                let bd = b.value.first?.date ?? .distantPast
                return ad > bd
            }
            .map { (key: $0.key, items: $0.value.sorted { lhs, rhs in
                // Pinned items always first, then by date desc
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                return lhs.date > rhs.date
            }) }
    }

    // MARK: - Date Separator

    private func dateSeparator(_ label: String, count: Int, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label.lowercased())
                    .font(.system(size: 11, weight: .regular).monospaced())
                    .foregroundStyle(waTextDim)
                    .tracking(1.2)
                Text("\(count)")
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(waTextDim)
                Spacer()
                if label != "Today" && label != "Yesterday" {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(waTextSec)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grouping

    private var filteredItems: [MiraItem] {
        if debouncedSearchText.isEmpty {
            let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10,
                                                    to: Calendar.current.startOfDay(for: Date()))!
            return store.items.filter {
                $0.status != .archived && $0.type != .request && $0.createdDate >= tenDaysAgo
            }
        } else {
            return store.search(debouncedSearchText).filter { $0.type != .request }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sync.agentOnline ? waAccent : waStatusAlert)
                .frame(width: 6, height: 6)
            if let hb = sync.heartbeat, hb.isBusy {
                Text("\(hb.activeCount ?? 0)")
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(waAccent)
            }
        }
    }
}

// MARK: - Attention Banner

struct AttentionBanner: View {
    let item: MiraItem

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(waStatusWarn).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15))
                    .foregroundStyle(waTextPri)
                    .lineLimit(1)
                Text("waiting for your reply")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waStatusWarn)
                    .tracking(0.5)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(waTextDim)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(waCardHi)
    }
}

// MARK: - Chat List Row

struct ChatListRow: View {
    let item: MiraItem
    @Environment(NotificationManager.self) private var notifications

    private var style: CategoryStyle { categoryStyle(for: item) }
    private var isUnread: Bool {
        notifications.isUnread(itemId: item.id, currentVersion: item.updatedAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Avatar — solid pastel block, dark icon for high contrast
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(style.color)
                    .frame(width: 38, height: 38)
                Image(systemName: style.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(waListBg)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(style.label)
                        .font(.system(size: 11, weight: .regular).monospaced())
                        .foregroundStyle(style.color)
                        .tracking(0.8)
                    if item.status == .needsInput {
                        Text("·  needs reply")
                            .font(.system(size: 11).monospaced())
                            .foregroundStyle(waStatusWarn)
                    }
                    if item.status == .failed {
                        Text("·  failed")
                            .font(.system(size: 11).monospaced())
                            .foregroundStyle(waStatusAlert)
                    }
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(waTextDim)
                    }
                }
                Text(item.title)
                    .font(.system(size: 15, weight: isUnread ? .semibold : .regular))
                    .foregroundStyle(isUnread ? waTextPri : waTextSec)
                    .lineLimit(1)
                if item.status == .working {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 10, height: 10)
                        statusText
                    }
                } else {
                    previewText
                }
            }
            Spacer(minLength: 8)
            Text(timeString)
                .font(.system(size: 11, weight: .regular).monospacedDigit())
                .foregroundStyle(waTextDim)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(
            ZStack {
                cardBg
                style.color.opacity(0.18)
            }
        )
    }

    private var previewText: some View {
        Group {
            if let last = item.messages.last(where: { $0.kind != .statusCard }) {
                Text(cleanPreview(last))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(waTextSec)
        .lineLimit(2)
    }

    private var statusText: some View {
        Group {
            if let last = item.messages.last, last.kind == .statusCard,
               let card = last.statusCard {
                Text(card.text)
            } else {
                Text("working")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(waAccent)
        .lineLimit(1)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(waTextDim)
            }
            if item.status == .needsInput {
                Text("needs reply")
                    .font(.system(size: 10, weight: .regular).monospaced())
                    .foregroundStyle(waStatusWarn)
                    .tracking(0.5)
            }
        }
    }

    private func cleanPreview(_ msg: ItemMessage) -> String {
        if msg.kind == .statusCard { return "" }
        return String(msg.content.prefix(100))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var timeString: String {
        let s = Date().timeIntervalSince(item.date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return Self.timeFormatter.string(from: item.date) }
        if s < 172800 { return "Yesterday" }
        return Self.dateFormatter.string(from: item.date)
    }
}

// MARK: - Shared Item Row (used elsewhere)

struct ItemRow: View {
    let item: MiraItem
    var body: some View {
        ChatListRow(item: item)
    }
}
