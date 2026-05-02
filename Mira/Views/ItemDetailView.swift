import SwiftUI
import MiraBridge
import SafariServices

struct ItemDetailView: View {
    let itemId: String
    @Environment(ItemStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(CommandWriter.self) private var commands
    @Environment(NotificationManager.self) private var notifications
    @State private var replyText = ""
    @State private var showTagEditor = false
    @State private var safariURL: URL?
    @FocusState private var inputFocused: Bool

    private var item: MiraItem? { store.item(for: itemId) }

    var body: some View {
        if let item = item {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(item.messages.reversed()) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .background(waChatBg)
                }

                // Error banner
                if let error = item.error {
                    ErrorBanner(error: error) {
                        commands.reply(to: itemId, content: "/retry")
                    }
                }

                // Reply input — allow two-way request/discussion threads, keep feeds one-way.
                if item.allowsReply {
                    replyBar(item: item)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(item.title.lowercased())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(waTextPri)
                        .lineLimit(1)
                        .tracking(0.2)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button { commands.pin(itemId: itemId, pinned: !item.pinned) } label: {
                            Label(item.pinned ? "Unpin" : "Pin",
                                  systemImage: item.pinned ? "pin.slash" : "pin")
                        }
                        Button { showTagEditor = true } label: {
                            Label("Tags", systemImage: "tag")
                        }
                        Divider()
                        Button(role: .destructive) {
                            commands.archive(itemId: itemId)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(waTextSec)
                    }
                }
            }
            .toolbarBackground(waListBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .environment(\.openURL, OpenURLAction { url in
                // Force in-app Safari (SFSafariViewController) so URLs always
                // open as web pages instead of being intercepted by Universal
                // Links into native apps (Reddit, Twitter, etc.).
                safariURL = url
                return .handled
            })
            .sheet(item: $safariURL) { url in
                SafariView(url: url).ignoresSafeArea()
            }
            .onAppear {
                notifications.markAsRead(itemId, version: item.updatedAt)
                sync.refreshDetail(itemId: itemId)
            }
        } else {
            ContentUnavailableView("Item not found",
                                   systemImage: "questionmark.circle",
                                   description: Text("This item may have been archived."))
        }
    }

    @ViewBuilder
    private func replyBar(item: MiraItem) -> some View {
        HStack(spacing: 10) {
            TextField("reply", text: $replyText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .font(.system(size: 14))
                .foregroundStyle(waTextPri)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(waCardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                commands.reply(to: itemId, content: text)
                replyText = ""
                inputFocused = false
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(replyText.isEmpty ? waTextDim : waListBg)
                    .frame(width: 36, height: 36)
                    .background(replyText.isEmpty ? waCardBg : waAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(replyText.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(waListBg)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ItemMessage
    @Environment(BridgeConfig.self) private var config
    @State private var loadedImage: UIImage?

    // Parse markdown preserving whitespace (so newlines/paragraphs survive),
    // then explicitly color and underline links so tap targets are obvious.
    private static var markdownCache: [String: AttributedString] = [:]

    private var cachedMarkdownContent: AttributedString {
        if let cached = Self.markdownCache[message.content] {
            return cached
        }
        // inlineOnlyPreservingWhitespace keeps line breaks and lists as
        // visible newlines, while still recognizing inline markdown
        // including [text](url) links.
        var result = (try? AttributedString(
            markdown: message.content,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(message.content)

        for run in result.runs {
            if run.link != nil {
                result[run.range].foregroundColor = waLink
                result[run.range].underlineStyle = .single
            }
        }
        Self.markdownCache[message.content] = result
        return result
    }

    var body: some View {
        switch message.kind {
        case .statusCard:
            statusCardView
        case .error:
            errorView
        case .text, .recall:
            textBubble
        }
    }

    // Bubble colors — derived from theme tokens
    private static let userBubbleColor = waOutBubble
    private static let agentBubbleColor = waCardBg

    private func loadImage() async {
        guard let path = message.imagePath else { return }

        // 1. Try iCloud file path
        if let artifactsURL = config.artifactsURL {
            let url = artifactsURL.appending(path: path)
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                loadedImage = img
                return
            }
            // Trigger iCloud download and poll briefly
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            for _ in 0..<6 {  // 3 seconds
                try? await Task.sleep(for: .milliseconds(500))
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    loadedImage = img
                    return
                }
            }
        }

        // 2. Fallback: fetch from LAN web server
        let serverBase = config.serverURL ?? BridgeConfig.defaultServerURL
        let profileId = config.profile?.id ?? "ang"
        let httpURL = serverBase.appending(path: "/api/\(profileId)/artifacts/\(path)")
        if let (data, response) = try? await MiraPinnedURLSession.shared.data(from: httpURL),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let img = UIImage(data: data) {
            loadedImage = img
        }
    }

    private var textBubble: some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 50) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if let uiImage = loadedImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: 280, maxHeight: 350)
                }
                Text(cachedMarkdownContent)
                    .font(.system(size: 14))
                    .foregroundStyle(waTextPri)
                    .tint(waLink)
                    .lineSpacing(2)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                Text(timeString)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(waTextDim)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            .background(message.isUser ? Self.userBubbleColor : Self.agentBubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if message.isAgent { Spacer(minLength: 50) }
        }
        .task(id: message.imagePath) { await loadImage() }
    }

    private var statusCardView: some View {
        HStack(spacing: 6) {
            if let card = message.statusCard {
                Image(systemName: card.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(waAccent)
                Text(card.text)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
                    .tracking(0.5)
            }
        }
        .padding(.vertical, 4)
    }

    private var errorView: some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(waStatusAlert)
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundStyle(waTextPri)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(waStatusAlert.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(timeString)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(waTextDim)
            }
            Spacer(minLength: 40)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: message.date)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let error: ItemError
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(waStatusAlert)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.message)
                    .font(.system(size: 13))
                    .foregroundStyle(waTextPri)
                Text(error.code)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
            }
            Spacer()
            if error.retryable {
                Button(action: onRetry) {
                    Text("retry")
                        .font(.system(size: 12).monospaced())
                        .foregroundStyle(waListBg)
                        .tracking(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(waStatusAlert)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(waStatusAlert.opacity(0.12))
    }
}

// MARK: - SFSafariViewController wrapper

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.preferredBarTintColor = UIColor(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x22/255.0, alpha: 1)
        vc.preferredControlTintColor = UIColor(red: 0x8F/255.0, green: 0xE5/255.0, blue: 0xB8/255.0, alpha: 1)
        vc.dismissButtonStyle = .done
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
