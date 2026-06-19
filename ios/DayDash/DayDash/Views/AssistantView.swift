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
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "What should I do first?",
        "Break my focus task into 3 small steps",
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

        Task {
            do {
                let reply = try await claude.send(system: systemPrompt(), messages: messages)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    messages.append(ChatMessage(role: .assistant, text: reply))
                }
                Haptics.soft()
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
