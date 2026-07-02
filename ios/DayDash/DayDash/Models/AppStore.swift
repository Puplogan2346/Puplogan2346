import Foundation
import Observation

/// The single source of truth for the app. Holds tasks, habits, and notes,
/// persists them to disk as JSON, and exposes a few derived values the dashboard uses.
///
/// All mutations go through the methods below so persistence happens in exactly one place
/// per change — we deliberately avoid `didSet` observers, which don't compose cleanly with
/// the `@Observable` macro (it rewrites stored properties into computed accessors).
@Observable
final class AppStore {
    private(set) var tasks: [TaskItem] = []
    private(set) var habits: [Habit] = []
    private(set) var notes: [Note] = []

    /// The user's first name, used for friendly greetings.
    private(set) var userName: String = ""

    /// Which task the user wants to focus on right now (ADHD-friendly "one thing").
    private(set) var focusedTaskID: UUID?

    init() {
        userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        if let raw = UserDefaults.standard.string(forKey: "focusedTaskID") {
            focusedTaskID = UUID(uuidString: raw)
        }
        tasks = load([TaskItem].self, from: .tasks) ?? AppStore.sampleTasks
        habits = load([Habit].self, from: .habits) ?? AppStore.sampleHabits
        notes = load([Note].self, from: .notes) ?? []
        syncWidget()
    }

    /// Publish a fresh snapshot for the Home Screen widget.
    func syncWidget() {
        SharedStore.write(WidgetSnapshot(
            greeting: Theme.greeting(),
            focusTitle: focusedTask?.title,
            doneTasks: doneTasksToday,
            totalTasks: openTasks.count + doneTasksToday,
            habitsDone: habitsDoneToday,
            habitsTotal: habits.count,
            updated: Date()
        ))
    }

    // MARK: - Derived values

    var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }

    var doneTasksToday: Int {
        tasks.filter { $0.isDone && Calendar.current.isDateInToday($0.completedAt ?? .distantPast) }.count
    }

    /// 0...1 progress for the day's ring.
    var dayProgress: Double {
        let total = openTasks.count + doneTasksToday
        guard total > 0 else { return 0 }
        return Double(doneTasksToday) / Double(total)
    }

    var habitsDoneToday: Int { habits.filter { $0.isDone() }.count }

    var focusedTask: TaskItem? {
        guard let id = focusedTaskID else { return nil }
        return tasks.first { $0.id == id && !$0.isDone }
    }

    /// Tasks completed on each of the last 7 days (oldest first) — feeds the Momentum chart.
    var weekCompletions: [DayCompletion] {
        let cal = Calendar.current
        return (0..<7).reversed().map { offset in
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date())
            let count = tasks.filter { task in
                guard task.isDone, let done = task.completedAt else { return false }
                return cal.isDate(done, inSameDayAs: day)
            }.count
            return DayCompletion(date: day, count: count)
        }
    }

    // MARK: - Settings mutations

    func setUserName(_ name: String) {
        userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(userName, forKey: "userName")
    }

    func setFocus(_ id: UUID?) {
        focusedTaskID = id
        if let id { UserDefaults.standard.set(id.uuidString, forKey: "focusedTaskID") }
        else { UserDefaults.standard.removeObject(forKey: "focusedTaskID") }
        syncWidget()
    }

    // MARK: - Task mutations

    func addTask(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.insert(TaskItem(title: trimmed), at: 0)
        persist(tasks, to: .tasks)
        syncWidget()
    }

    func toggleTask(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(of: task) else { return }
        tasks[idx].toggle()
        if tasks[idx].isDone && focusedTaskID == task.id { setFocus(nil) }
        persist(tasks, to: .tasks)
        syncWidget()
    }

    func deleteTasks(at offsets: IndexSet, in list: [TaskItem]) {
        let ids = offsets.map { list[$0].id }
        tasks.removeAll { ids.contains($0.id) }
        persist(tasks, to: .tasks)
        syncWidget()
    }

    // MARK: - Habit mutations

    func addHabit(name: String, emoji: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        habits.append(Habit(name: trimmed, emoji: emoji.isEmpty ? "✅" : emoji))
        persist(habits, to: .habits)
        syncWidget()
    }

    func toggleHabit(_ habit: Habit) {
        guard let idx = habits.firstIndex(of: habit) else { return }
        habits[idx].toggle()
        persist(habits, to: .habits)
        syncWidget()
    }

    func deleteHabits(at offsets: IndexSet) {
        habits.remove(atOffsets: offsets)
        persist(habits, to: .habits)
        syncWidget()
    }

    // MARK: - Note mutations

    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.insert(Note(text: trimmed), at: 0)
        persist(notes, to: .notes)
    }

    func deleteNotes(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        persist(notes, to: .notes)
    }

    /// Promote a brain-dump note into a task (the note is consumed).
    func makeTask(from note: Note) {
        addTask(note.text)
        notes.removeAll { $0.id == note.id }
        persist(notes, to: .notes)
    }

    // MARK: - Persistence

    private enum Store: String { case tasks, habits, notes }

    private func url(for store: Store) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daydash-\(store.rawValue).json")
    }

    private func persist<T: Encodable>(_ value: T, to store: Store) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(for: store), options: .atomic)
    }

    private func load<T: Decodable>(_ type: T.Type, from store: Store) -> T? {
        guard let data = try? Data(contentsOf: url(for: store)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - First-run sample content

    static let sampleTasks: [TaskItem] = [
        TaskItem(title: "Drink a glass of water 💧"),
        TaskItem(title: "Pick ONE thing to focus on today"),
        TaskItem(title: "Tap the ✨ to get your daily briefing")
    ]

    static let sampleHabits: [Habit] = [
        Habit(name: "Move my body", emoji: "🏃"),
        Habit(name: "Read 10 min", emoji: "📚"),
        Habit(name: "No doomscrolling", emoji: "🧘")
    ]
}
