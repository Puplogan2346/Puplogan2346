import Foundation

// MARK: - Day keys
//
// Habits are tracked per calendar day. We store days as "yyyy-MM-dd" strings so the
// data is trivially Codable and timezone-stable for display purposes.
enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = .current
        return f
    }()

    static func string(for date: Date = Date()) -> String {
        formatter.string(from: date)
    }
}

// MARK: - Task

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var isDone = false
    var notes: String = ""
    var createdAt = Date()
    var completedAt: Date?

    mutating func toggle() {
        isDone.toggle()
        completedAt = isDone ? Date() : nil
    }
}

// MARK: - Habit

struct Habit: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var emoji: String = "✅"
    /// Days this habit was completed, as "yyyy-MM-dd" strings.
    var doneDays: [String] = []

    func isDone(on date: Date = Date()) -> Bool {
        doneDays.contains(DayKey.string(for: date))
    }

    mutating func toggle(on date: Date = Date()) {
        let key = DayKey.string(for: date)
        if let idx = doneDays.firstIndex(of: key) {
            doneDays.remove(at: idx)
        } else {
            doneDays.append(key)
        }
    }

    /// Number of consecutive days (ending today) the habit was completed.
    var currentStreak: Int {
        let done = Set(doneDays)
        var streak = 0
        var day = Date()
        // Today only counts if it's actually done; otherwise we start from yesterday
        // so a not-yet-checked-off habit still shows last night's streak.
        if !done.contains(DayKey.string(for: day)) {
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
            if !done.contains(DayKey.string(for: day)) { return 0 }
        }
        while done.contains(DayKey.string(for: day)) {
            streak += 1
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }
}

// MARK: - Brain dump note

struct Note: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var createdAt = Date()
}

// MARK: - Calendar event (a lightweight, view-friendly copy of an EKEvent)

struct DayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarColorHex: String?

    var timeLabel: String {
        if isAllDay { return "All day" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: start)
    }
}

// MARK: - Chat

struct ChatMessage: Identifiable, Hashable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}
