import SwiftUI
import MiraBridge

struct TodoView: View {
    @Environment(TodoStore.self) private var store
    @State private var newText = ""
    @State private var selectedId: String?
    @FocusState private var inputFocused: Bool

    @State private var showStale = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                waListBg.ignoresSafeArea()
                    .onTapGesture { inputFocused = false }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Input
                        HStack(spacing: 10) {
                            TextField("add (or \"high: ...\")", text: $newText)
                                .textFieldStyle(.plain)
                                .focused($inputFocused)
                                .font(.system(size: 14))
                                .foregroundStyle(waTextPri)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(waCardBg)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onSubmit { addTodo() }
                            Button { addTodo() } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(waListBg)
                                    .frame(width: 36, height: 36)
                                    .background(waAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        if !store.working.isEmpty {
                            todoSection("working", count: activeWorking.count, items: activeWorking)
                            if staleWorking.count > 0 {
                                Button { showStale.toggle() } label: {
                                    Text(showStale
                                         ? "hide \(staleWorking.count) stale"
                                         : "show \(staleWorking.count) stale")
                                        .font(.system(size: 11).monospaced())
                                        .foregroundStyle(waTextDim)
                                        .tracking(1.2)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 6)
                                }
                                if showStale {
                                    todoSection("stale", count: staleWorking.count, items: staleWorking)
                                }
                            }
                        }
                        if !store.pending.isEmpty {
                            todoSection("pending", count: store.pending.count, items: store.pending)
                        }
                        if !store.done.isEmpty {
                            todoSection("done", count: min(10, store.done.count), items: Array(store.done.prefix(10)))
                        }

                        Spacer(minLength: 80)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("todo")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(waTextPri)
                        .tracking(0.3)
                }
            }
            .sheet(isPresented: Binding(
                get: { selectedId != nil },
                set: { if !$0 { selectedId = nil } }
            )) {
                if let id = selectedId {
                    TodoDetailSheet(todoId: id)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                }
            }
            .refreshable { store.refresh() }
            .onAppear { store.refresh() }
        }
    }

    // Working items split: anything with no createdAt OR older than 14d → stale
    private var activeWorking: [MiraTodo] {
        let cutoff = Date().addingTimeInterval(-14 * 24 * 3600)
        return store.working.filter { $0.date >= cutoff && !$0.createdAt.isEmpty }
    }
    private var staleWorking: [MiraTodo] {
        let cutoff = Date().addingTimeInterval(-14 * 24 * 3600)
        return store.working.filter { $0.date < cutoff || $0.createdAt.isEmpty }
    }

    @ViewBuilder
    private func todoSection(_ title: String, count: Int, items: [MiraTodo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
                    .tracking(1.2)
                Text("\(count)")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, todo in
                    TodoRow(todo: todo, selectedId: $selectedId)
                    if idx < items.count - 1 {
                        Rectangle().fill(waBorder).frame(height: 0.5).padding(.leading, 18)
                    }
                }
            }
        }
    }

    private func addTodo() {
        let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        newText = ""
        inputFocused = false
        // Parse priority: "high: do something"
        let prefixes = ["high", "medium", "low"]
        var priority = "medium"
        var title = t
        for p in prefixes {
            if t.lowercased().hasPrefix(p + ":") || t.lowercased().hasPrefix(p + " ") {
                priority = p
                title = String(t.dropFirst(p.count + 1)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        store.add(title: title, priority: priority)
    }
}

// MARK: - Todo Row

struct TodoRow: View {
    let todo: MiraTodo
    @Binding var selectedId: String?
    @Environment(TodoStore.self) private var store

    var body: some View {
        Button { selectedId = todo.id } label: {
            HStack(alignment: .top, spacing: 14) {
                // Priority dot
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(todo.priority)
                            .font(.system(size: 11).monospaced())
                            .foregroundStyle(priorityColor)
                            .tracking(0.8)
                        if !todo.followups.isEmpty {
                            Text("·  \(todo.followups.count) note\(todo.followups.count == 1 ? "" : "s")")
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(waTextDim)
                        }
                    }
                    Text(todo.title)
                        .font(.system(size: 15))
                        .foregroundStyle(todo.status == "done" ? waTextDim : waTextPri)
                        .strikethrough(todo.status == "done")
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(relativeTime)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(waTextDim)
                    if todo.status != "done" {
                        Button {
                            store.complete(todo.id)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(waListBg)
                                .frame(width: 22, height: 22)
                                .background(waAccent)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                ZStack { waCardBg; priorityColor.opacity(0.10) }
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.remove(todo.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                let next = todo.priority == "high" ? "medium" : todo.priority == "medium" ? "low" : "high"
                store.updatePriority(todo.id, to: next)
            } label: {
                Label("Priority", systemImage: "arrow.up.arrow.down")
            }
            .tint(.orange)
        }
    }

    private var priorityColor: Color {
        switch todo.priority {
        case "high":   return colorAlert      // sunset orange
        case "low":    return colorWriting    // mint
        default:       return colorAnalysis   // honey
        }
    }

    private var relativeTime: String {
        if todo.createdAt.isEmpty { return "—" }
        let s = Date().timeIntervalSince(todo.date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }
}

// MARK: - Todo Detail Sheet

struct TodoDetailSheet: View {
    let todoId: String
    @Environment(TodoStore.self) private var store
    @Environment(CommandWriter.self) private var commands
    @Environment(\.dismiss) private var dismiss
    @State private var replyText = ""

    private var todo: MiraTodo? { store.todos.first { $0.id == todoId } }

    var body: some View {
        NavigationStack {
            if let todo {
                VStack(spacing: 0) {
                    // Info header
                    HStack {
                        Text(todo.priority.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(priorityColor(todo.priority))
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(todo.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(todo.date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    // Chat-style followups
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            // Original todo as first message
                            HStack {
                                Spacer(minLength: 50)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(todo.title)
                                        .font(.body)
                                        .foregroundStyle(Color(hex: 0xE9EDEF))
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .background(Color(hex: 0x005C4B))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            // Followups
                            ForEach(Array(todo.followups.enumerated()), id: \.offset) { _, fu in
                                HStack {
                                    if fu.source != "agent" { Spacer(minLength: 50) }
                                    VStack(alignment: fu.source == "agent" ? .leading : .trailing, spacing: 2) {
                                        Text(mdAttributed(fu.content))
                                            .font(.body)
                                            .foregroundStyle(Color(hex: 0xE9EDEF))
                                            .tint(Color(hex: 0x53BDEB))
                                            .textSelection(.enabled)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                        HStack(spacing: 4) {
                                            if fu.source == "agent" {
                                                Text("Agent")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(waAccent)
                                            }
                                            Text(fu.date, style: .time)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.bottom, 4)
                                    }
                                    .background(fu.source == "agent" ? Color(hex: 0x202C33) : Color(hex: 0x005C4B))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    if fu.source == "agent" { Spacer(minLength: 50) }
                                }
                            }
                        }
                        .padding()
                    }

                    // Reply bar
                    if todo.status != "done" {
                        HStack(spacing: 8) {
                            TextField("Add followup...", text: $replyText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(1...5)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 18))

                            Button {
                                let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { return }
                                store.addFollowup(todoId, content: text)
                                commands.todoFollowup(todoId: todoId, content: text)
                                replyText = ""
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(replyText.isEmpty ? waTextSec : waAccent)
                            }
                            .disabled(replyText.isEmpty)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .navigationTitle(todo.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if todo.status != "done" {
                        ToolbarItem(placement: .primaryAction) {
                            Button { store.complete(todoId); dismiss() } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(waAccent)
                            }
                        }
                    }
                }
            }
        }
    }

    private func priorityColor(_ p: String) -> Color {
        switch p {
        case "high": return .red
        case "low": return .green
        default: return .yellow
        }
    }

    private func mdAttributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(s)
    }
}
