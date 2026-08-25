import SwiftUI
import Charts

/// The home dashboard: everything about *today* in one calm, premium, scrollable place.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var calendar = CalendarService()
    @State private var showingSettings = false
    @State private var showingBriefing = false
    @State private var quickAdd = ""
    @State private var appeared = false
    @State private var celebrating = false
    // Chosen once when the view is created so it doesn't re-randomize on every re-render.
    @State private var encouragement = Theme.encouragement
    @FocusState private var quickAddFocused: Bool

    // Recomputed when the app returns to the foreground so the greeting/background stay
    // correct if DayDash is left open across a daypart boundary or midnight.
    @State private var daypart = Theme.Daypart.current()

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TimeOfDayBackground(daypart: daypart)

                ScrollView {
                    VStack(spacing: Theme.cardSpacing) {
                        header
                        progressCard
                        focusCard
                        eventsCard
                        habitsGlance
                        momentumCard
                        quickCapture
                        Color.clear.frame(height: 8)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.tap(); showingBriefing = true } label: {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(Theme.terracotta)
                    }
                    .accessibilityLabel("Daily briefing")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(calendar: calendar) }
            .sheet(isPresented: $showingBriefing) { BriefingView(calendar: calendar) }
            .task {
                if calendar.access == .granted { await calendar.loadToday() }
                withAnimation(.smooth(duration: 0.5)) { appeared = true }
            }
            .onChange(of: store.dayProgress) { old, new in
                // Fire the celebration exactly when the last open task is completed.
                if new >= 1, old < 1, store.doneTasksToday > 0 {
                    celebrating = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // Refresh time-of-day theming and reload today's events on re-entry.
                daypart = Theme.Daypart.current()
                if calendar.access == .granted {
                    Task { await calendar.loadToday() }
                }
            }
            .overlay {
                if celebrating {
                    CelebrationOverlay { celebrating = false }
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateLine.uppercased())
                .font(Theme.rounded(.caption, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(store.userName.isEmpty
                 ? daypart.greeting + "."
                 : "\(daypart.greeting), \(store.userName).")
                .font(Theme.rounded(.largeTitle, weight: .bold))
            Text(encouragement)
                .font(Theme.rounded(.subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    // MARK: - Progress

    private var progressCard: some View {
        Card {
            HStack(spacing: 20) {
                ProgressRing(
                    progress: store.dayProgress,
                    label: "\(store.doneTasksToday)/\(store.openTasks.count + store.doneTasksToday)",
                    caption: "tasks"
                )
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 12) {
                    glanceRow(icon: "checklist", tint: Theme.terracotta,
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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(value)
                .font(Theme.rounded(.headline))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label).foregroundStyle(.secondary)
        }
        .font(Theme.rounded(.subheadline))
    }

    // MARK: - Focus hero

    private var focusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Right now, focus on", systemImage: "scope")
                    .font(Theme.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)

                if let task = store.focusedTask {
                    Text(task.title)
                        .font(Theme.rounded(.title2, weight: .semibold))
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { store.toggleTask(task) }
                        Haptics.success()
                    } label: {
                        Label("Mark done", systemImage: "checkmark.circle.fill")
                            .font(Theme.rounded(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(Theme.terracotta)
                } else if let suggestion = store.openTasks.first {
                    Text("Pick one thing so you're not juggling everything at once.")
                        .foregroundStyle(.secondary)
                        .font(Theme.rounded(.subheadline))
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { store.setFocus(suggestion.id) }
                        Haptics.selection()
                    } label: {
                        Label("Focus: \(suggestion.title)", systemImage: "scope")
                            .font(Theme.rounded(.headline))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(Theme.terracotta)
                } else {
                    Text("Nothing queued. Add a task below to get rolling. 🎉")
                        .foregroundStyle(.secondary)
                        .font(Theme.rounded(.subheadline))
                }
            }
        }
    }

    // MARK: - Calendar

    private var eventsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Today's calendar", systemImage: "calendar")
                    .font(Theme.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)

                switch calendar.access {
                case .granted:
                    if calendar.todayEvents.isEmpty {
                        Text("No events today. Enjoy the open space. 🌤️")
                            .foregroundStyle(.secondary)
                            .font(Theme.rounded(.subheadline))
                    } else {
                        ForEach(calendar.todayEvents.prefix(5)) { event in
                            HStack(spacing: 12) {
                                Capsule()
                                    .fill(Color(hex: event.calendarColorHex) ?? Theme.terracotta)
                                    .frame(width: 4, height: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(Theme.rounded(.subheadline, weight: .medium))
                                        .lineLimit(1)
                                    Text(event.timeLabel)
                                        .font(Theme.rounded(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                case .denied:
                    Text("Calendar access is off. Turn it on in Settings to see your day here.")
                        .foregroundStyle(.secondary)
                        .font(Theme.rounded(.subheadline))
                case .unknown:
                    Button {
                        Haptics.tap()
                        Task { await calendar.requestAccessAndLoad() }
                    } label: {
                        Label("Connect my calendar", systemImage: "link")
                            .font(Theme.rounded(.subheadline, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.terracotta)
                }
            }
        }
    }

    // MARK: - Habits glance

    private var habitsGlance: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Habits", systemImage: "flame.fill")
                    .font(Theme.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)
                if store.habits.isEmpty {
                    Text("Add a habit on the Habits tab to start a streak.")
                        .foregroundStyle(.secondary)
                        .font(Theme.rounded(.subheadline))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(store.habits) { habit in
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { store.toggleHabit(habit) }
                                    Haptics.soft()
                                } label: {
                                    VStack(spacing: 6) {
                                        Text(habit.emoji)
                                            .font(.title2)
                                            .symbolEffect(.bounce, value: habit.isDone())
                                        Text(habit.name)
                                            .font(Theme.rounded(.caption2, weight: .medium))
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(width: 80, height: 80)
                                    .background(
                                        habit.isDone() ? Theme.terracotta.opacity(0.18) : Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(habit.isDone() ? Theme.terracotta.opacity(0.4) : .clear, lineWidth: 1)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if habit.isDone() {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .padding(6)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }
        }
    }

    // MARK: - Momentum (7-day completions)

    private var momentumCard: some View {
        let week = store.weekCompletions
        let peak = week.map(\.count).max() ?? 0
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Momentum", systemImage: "chart.bar.fill")
                    .font(Theme.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)

                Chart(week) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Done", day.count),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.amber, Theme.terracotta],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(5)
                }
                .chartYScale(domain: 0...Double(max(peak, 3)))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                            .font(Theme.rounded(.caption2, weight: .medium))
                    }
                }
                .frame(height: 92)

                Text(peak == 0
                     ? "Finish a task and your week starts filling in."
                     : "Tasks finished each day this week.")
                    .font(Theme.rounded(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Quick capture

    private var quickCapture: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Quick add a task", systemImage: "plus.circle.fill")
                    .font(Theme.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    TextField("What needs doing?", text: $quickAdd)
                        .font(Theme.rounded(.body))
                        .focused($quickAddFocused)
                        .padding(12)
                        .background(Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .submitLabel(.done)
                        .onSubmit(commitQuickAdd)
                    Button(action: commitQuickAdd) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white, Theme.terracotta)
                    }
                    .buttonStyle(.pressable)
                    .disabled(quickAdd.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func commitQuickAdd() {
        guard !quickAdd.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { store.addTask(quickAdd) }
        quickAdd = ""
        Haptics.success()
    }
}
