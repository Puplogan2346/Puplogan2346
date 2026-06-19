import SwiftUI

/// The home dashboard: everything about *today* in one calm, scrollable place.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var calendar = CalendarService()
    @State private var showingSettings = false
    @State private var showingBriefing = false
    @State private var quickAdd = ""

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    progressCard
                    focusCard
                    eventsCard
                    habitsGlance
                    quickCapture
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingBriefing = true } label: {
                        Image(systemName: "sparkles").font(.headline)
                    }
                    .accessibilityLabel("Daily briefing")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(calendar: calendar) }
            .sheet(isPresented: $showingBriefing) { BriefingView(calendar: calendar) }
            .task {
                if calendar.access == .granted { await calendar.loadToday() }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateLine.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(store.userName.isEmpty
                 ? Theme.greeting() + "."
                 : "\(Theme.greeting()), \(store.userName).")
                .font(.largeTitle.bold())
            Text(Theme.encouragement)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressCard: some View {
        Card {
            HStack(spacing: 18) {
                ProgressRing(
                    progress: store.dayProgress,
                    label: "\(store.doneTasksToday)/\(store.openTasks.count + store.doneTasksToday)",
                    caption: "tasks"
                )
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 10) {
                    glanceRow(icon: "checklist", tint: .accentColor,
                              value: "\(store.openTasks.count)", label: "to do")
                    glanceRow(icon: "flame.fill", tint: .orange,
                              value: "\(store.habitsDoneToday)/\(store.habits.count)", label: "habits")
                    glanceRow(icon: "calendar", tint: .blue,
                              value: "\(calendar.todayEvents.count)", label: "events")
                }
            }
        }
    }

    private func glanceRow(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
            Text(value).font(.headline).monospacedDigit()
            Text(label).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private var focusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Right now, focus on", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let task = store.focusedTask {
                    Text(task.title).font(.title3.weight(.semibold))
                    Button {
                        withAnimation { store.toggleTask(task) }
                        Haptics.success()
                    } label: {
                        Label("Mark done", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if let suggestion = store.openTasks.first {
                    Text("Pick one thing so you're not juggling everything at once.")
                        .foregroundStyle(.secondary)
                    Button {
                        withAnimation { store.setFocus(suggestion.id) }
                    } label: {
                        Label("Focus: \(suggestion.title)", systemImage: "scope")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Text("Nothing queued. Add a task below to get rolling. 🎉")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var eventsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Today's calendar", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                switch calendar.access {
                case .granted:
                    if calendar.todayEvents.isEmpty {
                        Text("No events today. Enjoy the open space. 🌤️")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(calendar.todayEvents.prefix(5)) { event in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: event.calendarColorHex) ?? .accentColor)
                                    .frame(width: 4, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Text(event.timeLabel).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                case .denied:
                    Text("Calendar access is off. Turn it on in Settings to see your day here.")
                        .foregroundStyle(.secondary)
                case .unknown:
                    Button {
                        Task { await calendar.requestAccessAndLoad() }
                    } label: {
                        Label("Connect my calendar", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var habitsGlance: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Habits", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if store.habits.isEmpty {
                    Text("Add a habit on the Habits tab to start a streak.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.habits) { habit in
                                Button {
                                    withAnimation { store.toggleHabit(habit) }
                                    Haptics.tap()
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(habit.emoji).font(.title2)
                                        Text(habit.name).font(.caption2).lineLimit(1)
                                    }
                                    .frame(width: 76, height: 76)
                                    .background(
                                        habit.isDone() ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if habit.isDone() {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green).padding(5)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var quickCapture: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Quick add a task", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("What needs doing?", text: $quickAdd)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitQuickAdd)
                    Button("Add", action: commitQuickAdd)
                        .buttonStyle(.borderedProminent)
                        .disabled(quickAdd.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func commitQuickAdd() {
        store.addTask(quickAdd)
        quickAdd = ""
        Haptics.tap()
    }
}
