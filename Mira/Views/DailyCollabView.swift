import SwiftUI
import MiraBridge

struct DailyCollabView: View {
    @Environment(ItemStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(CommandWriter.self) private var commands
    @Environment(NotificationManager.self) private var notifications
    @State private var didRequestThread = false
    @State private var replyText = ""
    @FocusState private var inputFocused: Bool

    private var collabItem: MiraItem? {
        store.item(for: CommandWriter.dailyCollabItemId)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item = collabItem {
                    chatView(item: item)
                } else {
                    ZStack {
                        waChatBg.ignoresSafeArea()
                        ProgressView()
                            .tint(waAccent)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(sync.agentOnline ? waAccent : waStatusWarn)
                            .frame(width: 7, height: 7)
                        Text("Mira")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(waTextPri)
                    }
                }
            }
            .toolbarBackground(waListBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            sync.refresh {
                ensureThread()
                sync.refreshDetail(itemId: CommandWriter.dailyCollabItemId, messagesPerItem: 200)
            }
        }
        .onChange(of: store.items) { _, _ in
            ensureThread()
        }
    }

    private func chatView(item: MiraItem) -> some View {
        let messages = chatMessages(for: item)

        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            CollabMessageBubble(message: message)
                                .id(message.id)
                        }
                        if isActive(item.status) {
                            CollabThinkingRow()
                                .id("collab-thinking")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .background(waChatBg)
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    notifications.markAsRead(item.id, version: item.updatedAt)
                    sync.refreshDetail(itemId: item.id, messagesPerItem: 200)
                    scrollToLatest(proxy: proxy, messages: messages, status: item.status, animated: false)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToLatest(proxy: proxy, messages: messages, status: item.status)
                }
                .onChange(of: item.status) { _, _ in
                    scrollToLatest(proxy: proxy, messages: messages, status: item.status)
                }
            }

            if let error = item.error {
                CollabErrorRow(error: error) {
                    commands.reply(to: CommandWriter.dailyCollabItemId, content: "/retry")
                }
            }

            replyBar
        }
        .background(waChatBg.ignoresSafeArea())
    }

    private var replyBar: some View {
        HStack(spacing: 10) {
            TextField("message Mira", text: $replyText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .submitLabel(.send)
                .font(.system(size: 15))
                .foregroundStyle(waTextPri)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(waCardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit(sendReply)

            Button(action: sendReply) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(canSend ? waListBg : waTextDim)
                    .frame(width: 38, height: 38)
                    .background(canSend ? waAccent : waCardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(waListBg)
    }

    private var canSend: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commands.reply(to: CommandWriter.dailyCollabItemId, content: text)
        replyText = ""
        inputFocused = false
    }

    private func chatMessages(for item: MiraItem) -> [ItemMessage] {
        item.messages
            .filter { $0.kind == .text || $0.kind == .recall }
            .sorted { $0.date < $1.date }
    }

    private func isActive(_ status: ItemStatus) -> Bool {
        switch status {
        case .queued, .working, .verifying:
            return true
        case .needsInput, .done, .failed, .archived:
            return false
        }
    }

    private func scrollToLatest(
        proxy: ScrollViewProxy,
        messages: [ItemMessage],
        status: ItemStatus,
        animated: Bool = true
    ) {
        let action = {
            if isActive(status) {
                proxy.scrollTo("collab-thinking", anchor: .bottom)
            } else if let lastId = messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }

    private func ensureThread() {
        guard collabItem == nil, !didRequestThread else { return }
        didRequestThread = true
        commands.createDailyCollabThread()
    }
}

private struct CollabMessageBubble: View {
    let message: ItemMessage

    private var markdownContent: AttributedString {
        var result = (try? AttributedString(
            markdown: message.content,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(message.content)

        for run in result.runs where run.link != nil {
            result[run.range].foregroundColor = waLink
            result[run.range].underlineStyle = .single
        }
        return result
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 46) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(markdownContent)
                    .font(.system(size: 15))
                    .foregroundStyle(waTextPri)
                    .tint(waLink)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                Text(timeString)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(waTextDim)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            .background(message.isUser ? waOutBubble : waCardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if message.isAgent { Spacer(minLength: 46) }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: message.date)
    }
}

private struct CollabThinkingRow: View {
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(waTextDim)
                Text("thinking")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(waCardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 46)
        }
    }
}

private struct CollabErrorRow: View {
    let error: ItemError
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(waStatusAlert)
            Text(error.message)
                .font(.system(size: 13))
                .foregroundStyle(waTextPri)
                .lineLimit(2)
            Spacer()
            if error.retryable {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(waListBg)
                        .frame(width: 30, height: 30)
                        .background(waStatusAlert)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(waStatusAlert.opacity(0.12))
    }
}
