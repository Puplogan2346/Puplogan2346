import SwiftUI

/// A chat with Claude that knows about your day. ADHD-friendly: ask it to break a task
/// down, decide what to do first, or just talk through what's on your plate.
struct AssistantView: View {
    @Environment(AppStore.self) private var store
    @State private var claude = ClaudeService()
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isSending = false
    @State private var errorText: String?

    private let suggestions = [
        "What should I do first?",
        "Break my focus task into 3 small steps",
        "Plan a calm afternoon"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty { intro }
                            ForEach(messages) { bubble($0) }
                            if isSending {
                                HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
                                    .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                composer
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask your day ✨").font(.title2.bold())
            Text("I can see your tasks, habits, and focus. Try one of these:")
                .foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { s in
                Button {
                    input = s; send()
                } label: {
                    Text(s).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            if !claude.hasAPIKey {
                Label("Add your Claude API key in Settings (gear on the Today tab) to enable chat.",
                      systemImage: "key")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(12)
                .background(
                    message.role == .user ? Color.accentColor : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .id(message.id)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .padding(10)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.largeTitle)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        }
        .padding()
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        errorText = nil
        input = ""
        messages.append(ChatMessage(role: .user, text: text))
        isSending = true

        Task {
            do {
                let reply = try await claude.send(system: systemPrompt(), messages: messages)
                messages.append(ChatMessage(role: .assistant, text: reply))
            } catch {
                errorText = error.localizedDescription
            }
            isSending = false
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

        Today's context:
        Focus task: \(focus)
        Open tasks:
        \(tasks.isEmpty ? "(none)" : tasks)
        Habits:
        \(habits.isEmpty ? "(none)" : habits)
        """
    }
}
