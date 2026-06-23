import SwiftUI

/// A chat with Claude that knows about your day. ADHD-friendly: ask it to break a task
/// down, decide what to do first, or just talk through what's on your plate.
struct AssistantView: View {
    @Environment(AppStore.self) private var store
    @Environment(ClaudeService.self) private var claude
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isSending = false
    @State private var errorText: String?
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "What should I do first?",
        "Break my focus task into 3 small steps",
        "Add “call the dentist” to my tasks",
        "Plan a calm afternoon"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                if messages.isEmpty { intro }
                                ForEach(messages) { bubble($0) }
                                if isSending {
                                    TypingIndicator()
                                        .id("typing")
                                }
                            }
                            .padding()
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: messages.count) { _, _ in
                            withAnimation(.smooth) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                        }
                        .onChange(of: messages.last?.text) { _, _ in
                            // Keep the newest tokens in view as the reply streams in.
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                        .onChange(of: isSending) { _, sending in
                            if sending { withAnimation(.smooth) { proxy.scrollTo("typing", anchor: .bottom) } }
                        }
                    }

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.rounded(.footnote))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal).padding(.bottom, 4)
                    }

                    composer
                }
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.terracotta)
                Text("Ask your day").font(Theme.rounded(.title2, weight: .bold))
            }
            Text("I can see your tasks, habits, and focus. Try one of these:")
                .font(Theme.rounded(.subheadline))
                .foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { s in
                Button {
                    input = s; send()
                } label: {
                    HStack {
                        Text(s).font(Theme.rounded(.subheadline, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
            if !claude.hasAPIKey {
                Label("Add your Claude API key in Settings (profile icon on Today) to enable chat.",
                      systemImage: "key.fill")
                    .font(Theme.rounded(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 8)
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }
            Text(message.text)
                .font(Theme.rounded(.body))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background {
                    if message.role == .user {
                        LinearGradient(colors: [Theme.peach, Theme.terracotta],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Color(.secondarySystemBackground)
                    }
                }
                .foregroundStyle(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(message.role == .user ? 0.12 : 0.05), radius: 6, y: 3)
            if message.role == .assistant { Spacer(minLength: 44) }
        }
        .id(message.id)
        .transition(.move(edge: message.role == .user ? .trailing : .leading).combined(with: .opacity))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $input, axis: .vertical)
                .font(Theme.rounded(.body))
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white, Theme.terracotta)
            }
            .buttonStyle(.pressable)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        }
        .padding(12)
        .background(.thinMaterial)
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        errorText = nil
        input = ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages.append(ChatMessage(role: .user, text: text))
        }
        isSending = true
        Haptics.tap()

        // Snapshot everything needed for the request now, while the view is on-screen, so the
        // async work never reaches back into @Environment/@State for read-only inputs.
        let outgoing = messages
        let system = systemPrompt()
        let store = store

        // @MainActor: this view's @State (messages/isSending/errorText) must only be
        // mutated on the main actor. A bare `Task {}` here would be nonisolated.
        Task { @MainActor in
            var insertedID: UUID?
            var produced = false
            do {
                let stream = claude.streamAgent(
                    system: system,
                    history: outgoing,
                    tools: Self.tools,
                    runTool: { name, input in Self.execute(tool: name, input: input, store: store) }
                )
                for try await event in stream {
                    produced = true
                    switch event {
                    case .text(let delta):
                        if let id = insertedID, let idx = messages.firstIndex(where: { $0.id == id }) {
                            messages[idx].text += delta
                        } else {
                            // First token of a bubble: drop the typing indicator and start it.
                            isSending = false
                            let bubble = ChatMessage(role: .assistant, text: delta)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                messages.append(bubble)
                            }
                            insertedID = bubble.id
                            Haptics.soft()
                        }
                    case .toolResult(let summary):
                        isSending = false
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            messages.append(ChatMessage(role: .assistant, text: "✓ \(summary)"))
                        }
                        insertedID = nil   // any follow-up text starts a fresh bubble
                        Haptics.success()
                    }
                }
                if !produced {
                    messages.append(ChatMessage(role: .assistant, text: "(No response)"))
                }
            } catch is CancellationError {
                // User navigated away — nothing to surface.
            } catch {
                errorText = error.localizedDescription
            }
            isSending = false
        }
    }

    // MARK: - Tools Claude can call

    private static let tools: [ClaudeService.ToolSpec] = [
        .init(
            name: "add_task",
            description: "Add a new to-do task to the user's list. Use this whenever the user asks to add, remember, capture, or schedule something to do.",
            inputSchema: [
                "type": "object",
                "properties": ["title": ["type": "string", "description": "The task text, e.g. 'Email Sam about the invoice'"]],
                "required": ["title"]
            ]
        ),
        .init(
            name: "add_habit",
            description: "Add a daily habit the user wants to track and build a streak on.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "The habit name, e.g. 'Drink water'"],
                    "emoji": ["type": "string", "description": "A single emoji icon for the habit (optional)"]
                ],
                "required": ["name"]
            ]
        )
    ]

    /// Executes a tool call against the store. Runs on the main actor (store mutations are UI state).
    @MainActor
    private static func execute(tool name: String, input: [String: Any], store: AppStore) -> String {
        switch name {
        case "add_task":
            let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return "No task title was provided." }
            store.addTask(title)
            return "Added task “\(title)”."
        case "add_habit":
            let habitName = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !habitName.isEmpty else { return "No habit name was provided." }
            let emoji = (input["emoji"] as? String) ?? ""
            store.addHabit(name: habitName, emoji: emoji)
            return "Added habit “\(habitName)”."
        default:
            return "Unknown tool: \(name)."
        }
    }

    /// Give Claude the context of the user's day so answers are grounded and useful.
    private func systemPrompt() -> String {
        let tasks = store.openTasks.prefix(15).map { "- \($0.title)" }.joined(separator: "\n")
        let focus = store.focusedTask?.title ?? "none chosen yet"
        let habits = store.habits.map { "- \($0.name): \($0.isDone() ? "done today" : "not yet"), \($0.currentStreak)-day streak" }.joined(separator: "\n")
        let name = store.userName.isEmpty ? "the user" : store.userName

        return """
        You are DayDash, a warm, concise daily assistant for \(name). The user values calm, \
        ADHD-friendly help: short answers, concrete next steps, and no overwhelm. When asked what \
        to do, recommend ONE clear next action rather than a long list. Keep replies brief.

        You can act on the user's day with tools: use `add_task` when they want to remember or \
        capture something to do, and `add_habit` when they want to track a daily habit. Prefer \
        calling the tool over only describing it, then briefly confirm what you did.

        Today's context:
        Focus task: \(focus)
        Open tasks:
        \(tasks.isEmpty ? "(none)" : tasks)
        Habits:
        \(habits.isEmpty ? "(none)" : habits)
        """
    }
}

/// Animated three-dot "Claude is thinking" indicator.
private struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .phaseAnimator([0.3, 1.0]) { view, phase in
                        view.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.5).delay(Double(i) * 0.18)
                    }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
