import SwiftUI
import MiraBridge
import QuickLook

// MARK: - Artifact Categories

struct ArtifactCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
}

private let knownCategories: [ArtifactCategory] = [
    ArtifactCategory(id: "writings",  name: "writings",  icon: "doc.text",       color: colorWriting),
    ArtifactCategory(id: "briefings", name: "briefings", icon: "globe",          color: colorExplore),
    ArtifactCategory(id: "audio",     name: "audio",     icon: "waveform",       color: colorPodcast),
    ArtifactCategory(id: "video",     name: "video",     icon: "film",           color: colorAlert),
    ArtifactCategory(id: "photos",    name: "photos",    icon: "photo",          color: colorPhoto),
    ArtifactCategory(id: "research",  name: "research",  icon: "magnifyingglass", color: colorAnalysis),
]

// MARK: - Artifacts View (tab root)

struct ArtifactsView: View {
    @Environment(BridgeConfig.self) private var config

    var body: some View {
        NavigationStack {
            Group {
                if let artifactsURL = config.artifactsURL {
                    ArtifactsRootView(artifactsURL: artifactsURL)
                } else {
                    ContentUnavailableView(
                        "No folder set",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Select Bridge folder in Settings")
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("artifacts")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(waTextPri)
                        .tracking(0.3)
                }
            }
        }
    }
}

struct ArtifactsRootView: View {
    let artifactsURL: URL
    @State private var folders: [ArtifactFolder] = []

    var body: some View {
        ZStack {
            waListBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("collections")
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(waTextDim)
                        .tracking(1.2)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                    VStack(spacing: 0) {
                        ForEach(Array(folders.enumerated()), id: \.element.id) { idx, folder in
                            NavigationLink {
                                ArtifactFolderBrowser(folderURL: folder.url, title: folder.category?.name ?? folder.name)
                            } label: {
                                ArtifactFolderRow(folder: folder)
                            }
                            .buttonStyle(.plain)
                            if idx < folders.count - 1 {
                                Rectangle().fill(waBorder).frame(height: 0.5).padding(.leading, 18)
                            }
                        }
                    }
                    Spacer(minLength: 80)
                }
            }
            .refreshable { loadFolders() }
        }
        .onAppear { loadFolders() }
    }

    private func loadFolders() {
        let fm = FileManager.default
        // Trigger iCloud download for the artifacts root and known subdirs
        try? fm.startDownloadingUbiquitousItem(at: artifactsURL)
        for cat in knownCategories {
            try? fm.startDownloadingUbiquitousItem(at: artifactsURL.appendingPathComponent(cat.id))
        }

        guard fm.fileExists(atPath: artifactsURL.path) else {
            folders = []
            return
        }
        do {
            let contents = try fm.contentsOfDirectory(
                at: artifactsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let dirs = contents.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }

            // Known categories first (in defined order), then unknown folders
            let knownIds = Set(knownCategories.map(\.id))
            var result: [ArtifactFolder] = []

            for cat in knownCategories {
                if let url = dirs.first(where: { $0.lastPathComponent == cat.id }) {
                    let count = (try? fm.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") && !$0.hasPrefix("_") }.count) ?? 0
                    result.append(ArtifactFolder(name: cat.id, url: url, category: cat, itemCount: count))
                }
            }

            for url in dirs where !knownIds.contains(url.lastPathComponent) && !url.lastPathComponent.hasPrefix("_") {
                let name = url.lastPathComponent
                let count = (try? fm.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }.count) ?? 0
                result.append(ArtifactFolder(name: name, url: url, category: nil, itemCount: count))
            }

            folders = result
        } catch {
            folders = []
        }
    }
}

struct ArtifactFolder: Identifiable {
    let name: String
    let url: URL
    let category: ArtifactCategory?
    let itemCount: Int
    var id: String { url.path }
}

// MARK: - Folder Browser (Files-like)

struct ArtifactFolderBrowser: View {
    let folderURL: URL
    var title: String = ""
    @State private var items: [ArtifactItem] = []
    @State private var previewURL: URL?

    var body: some View {
        ZStack {
            waListBg.ignoresSafeArea()
            if items.isEmpty {
                VStack(spacing: 8) {
                    Text("empty")
                        .font(.system(size: 12).monospaced())
                        .foregroundStyle(waTextDim)
                        .tracking(1.2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            if item.isDirectory {
                                NavigationLink {
                                    ArtifactFolderBrowser(folderURL: item.url, title: item.name)
                                } label: {
                                    ArtifactItemRow(item: item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    triggerDownload(item.url)
                                    previewURL = item.url
                                } label: {
                                    ArtifactItemRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                            if idx < items.count - 1 {
                                Rectangle().fill(waBorder).frame(height: 0.5).padding(.leading, 18)
                            }
                        }
                        Spacer(minLength: 80)
                    }
                    .padding(.top, 8)
                }
                .refreshable { loadItems() }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !title.isEmpty {
                ToolbarItem(placement: .principal) {
                    Text(title.lowercased())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(waTextPri)
                        .tracking(0.3)
                }
            }
        }
        .onAppear { loadItems() }
        .quickLookPreview($previewURL)
    }

    private func loadItems() {
        let fm = FileManager.default
        try? fm.startDownloadingUbiquitousItem(at: folderURL)
        guard fm.fileExists(atPath: folderURL.path) else {
            items = []
            return
        }
        do {
            let contents = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            items = contents.compactMap { url in
                let name = url.lastPathComponent
                if name.hasPrefix("_") || name.hasPrefix(".") { return nil }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                let isDir = values?.isDirectory ?? false
                return ArtifactItem(
                    name: name,
                    url: url,
                    date: values?.contentModificationDate ?? .distantPast,
                    size: Int64(values?.fileSize ?? 0),
                    isDirectory: isDir,
                    childCount: isDir ? (try? fm.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") && !$0.hasPrefix("_") }.count) ?? 0 : 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.date > rhs.date
            }
        } catch {
            items = []
        }
    }

    private func triggerDownload(_ url: URL) {
        let fm = FileManager.default
        if !fm.isReadableFile(atPath: url.path) {
            try? fm.startDownloadingUbiquitousItem(at: url)
        }
    }
}

// MARK: - Item Model

struct ArtifactItem: Identifiable {
    let name: String
    let url: URL
    let date: Date
    let size: Int64
    let isDirectory: Bool
    let childCount: Int

    var id: String { url.path }
}

// MARK: - Item Row

struct ArtifactFolderRow: View {
    let folder: ArtifactFolder

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(folder.category?.color ?? waTextSec)
                    .frame(width: 38, height: 38)
                Image(systemName: folder.category?.icon ?? "folder")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(waListBg)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.category?.name ?? folder.name)
                    .font(.system(size: 15))
                    .foregroundStyle(waTextPri)
                Text("\(folder.itemCount) item\(folder.itemCount == 1 ? "" : "s")")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(waTextDim)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            ZStack {
                waCardBg
                (folder.category?.color ?? Color.clear).opacity(0.10)
            }
        )
    }
}

struct ArtifactItemRow: View {
    let item: ArtifactItem

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(iconColor(item.name).opacity(item.isDirectory ? 1.0 : 0.85))
                    .frame(width: 36, height: 36)
                Image(systemName: item.isDirectory ? "folder" : fileIcon(item.name))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(waListBg)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(item.name))
                    .font(.system(size: 14))
                    .foregroundStyle(waTextPri)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Text(formatDate(item.date))
                    if !item.isDirectory && item.size > 0 {
                        Text(formatSize(item.size))
                    }
                    if item.isDirectory && item.childCount > 0 {
                        Text("\(item.childCount) items")
                    }
                }
                .font(.system(size: 11).monospaced())
                .foregroundStyle(waTextDim)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(waCardBg)
    }

    private func displayName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt", "json":
            return (name as NSString).deletingPathExtension
        default:
            return name
        }
    }

    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt": return "doc.text"
        case "json": return "curlybraces"
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo"
        case "mp4", "mov", "m4v", "avi": return "film"
        case "mp3", "m4a", "wav", "aac", "flac": return "waveform"
        case "swift", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        case "epub": return "book"
        default: return "doc"
        }
    }

    private func iconColor(_ name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt":                                return colorWriting
        case "pdf":                                      return colorAlert
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return colorPhoto
        case "mp4", "mov", "m4v", "avi":                 return colorPodcast
        case "mp3", "m4a", "wav", "aac", "flac":         return colorPodcast
        case "swift", "py", "js", "ts":                  return colorCode
        case "json":                                     return colorCode
        case "epub":                                     return colorJournal
        default:                                         return colorAgent
        }
    }

    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let thisYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private static let oldFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private func formatDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.todayFormatter.string(from: date)
        } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
            return Self.thisYearFormatter.string(from: date)
        } else {
            return Self.oldFormatter.string(from: date)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
