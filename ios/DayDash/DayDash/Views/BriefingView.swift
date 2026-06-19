import SwiftUI

/// A one-tap AI "here's your day" summary — the thing you check in with each morning.
struct BriefingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var calendar: CalendarService

    @State private var claude = ClaudeService()
    @State private var briefing = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        HStack { ProgressView(); Text("Pulling your day together…") }
                            .foregroundStyle(.secondary)
                    } else if let errorText {
                        ContentUnavailableView {
                            Label("Couldn't generate a briefing", systemImage: "exclamationmark.bubble")
                        } description: {
                            Text(errorText)
                        } actions: {
                            Button("Try again") { Task { await generate() } }
                                .buttonStyle(.borderedProminent)
                        }
                    } else if briefing.isEmpty {
                        Text(localFallback).foregroundStyle(.secondary)
                    } else {
                        Text(briefing)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Daily Briefing ✨")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await generate() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(isLoading)
                }
            }
            .task { if claude.hasAPIKey { await generate() } }
        }
    }

    /// Shown when there's no API key — still useful, just not AI-written.
    private var localFallback: String {
        var lines = ["\(Theme.greeting()), \(store.userName.isEmpty ? "here's today" : store.userName)."]
        lines.append("• \(store.openTasks.count) open task(s), \(store.doneTasksToday) done so far.")
        if let f = store.focusedTask { lines.append("• Focus: \(f.title)") }
        lines.append("• \(calendar.todayEvents.count) calendar event(s).")
        lines.append("• \(store.habitsDoneToday)/\(store.habits.count) habits done.")
        lines.append("\nAdd a Claude API key in Settings for an AI-written briefing.")
        return lines.joined(separator: "\n")
    }

    private func generate() async {
        guard claude.hasAPIKey else { return }
        isLoading = true; errorText = nil
        let events = calendar.todayEvents.prefix(8)
            .map { "- \($0.timeLabel): \($0.title)" }.joined(separator: "\n")
        let tasks = store.openTasks.prefix(15).map { "- \($0.title)" }.joined(separator: "\n")
        let habits = store.habits.map { "- \($0.name) (\($0.isDone() ? "done" : "todo"))" }.joined(separator: "\n")

        let prompt = """
        Write me a short, warm morning briefing (4-6 sentences max). Be encouraging and calm, \
        ADHD-friendly. Suggest ONE thing to start with. Don't just list everything back — \
        synthesize it into a plan for the day.

        Open tasks:
        \(tasks.isEmpty ? "(none)" : tasks)
        Calendar:
        \(events.isEmpty ? "(no events)" : events)
        Habits:
        \(habits.isEmpty ? "(none)" : habits)
        """

        do {
            briefing = try await claude.send(
                system: "You are DayDash, a calm, supportive daily companion. Keep it brief.",
                messages: [ChatMessage(role: .user, text: prompt)]
            )
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
