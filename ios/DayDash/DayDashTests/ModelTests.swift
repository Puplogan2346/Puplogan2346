import XCTest
import SwiftUI
@testable import DayDash

/// Pure-logic tests for the value types. Deterministic — they inject dates rather than
/// relying on the wall clock, and touch no disk or network.
final class ModelTests: XCTestCase {

    // MARK: - Helpers

    /// A "yyyy-MM-dd" key for `daysAgo` days before today, in the current calendar.
    private func dayKey(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return DayKey.string(for: date)
    }

    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    // MARK: - TaskItem

    func testTaskToggleSetsAndClearsCompletedAt() {
        var task = TaskItem(title: "Write tests")
        XCTAssertFalse(task.isDone)
        XCTAssertNil(task.completedAt)

        task.toggle()
        XCTAssertTrue(task.isDone)
        XCTAssertNotNil(task.completedAt)

        task.toggle()
        XCTAssertFalse(task.isDone)
        XCTAssertNil(task.completedAt, "Un-completing a task should clear its completion date")
    }

    // MARK: - Habit.currentStreak

    func testNoDaysHasNoStreak() {
        XCTAssertEqual(Habit(name: "x", doneDays: []).currentStreak, 0)
    }

    func testDoneTodayStreakIsOne() {
        XCTAssertEqual(Habit(name: "x", doneDays: [dayKey(daysAgo: 0)]).currentStreak, 1)
    }

    func testConsecutiveDaysEndingTodayAreCounted() {
        let habit = Habit(name: "x", doneDays: [dayKey(daysAgo: 0), dayKey(daysAgo: 1), dayKey(daysAgo: 2)])
        XCTAssertEqual(habit.currentStreak, 3)
    }

    func testStreakCountsFromYesterdayWhenTodayNotYetDone() {
        // Not done today, but the previous two days are — the streak should still show 2
        // so an un-checked-off-today habit doesn't appear to have lost its run.
        let habit = Habit(name: "x", doneDays: [dayKey(daysAgo: 1), dayKey(daysAgo: 2)])
        XCTAssertEqual(habit.currentStreak, 2)
    }

    func testGapBreaksStreak() {
        // Done today and three days ago, but with a gap — only today counts.
        let habit = Habit(name: "x", doneDays: [dayKey(daysAgo: 0), dayKey(daysAgo: 3)])
        XCTAssertEqual(habit.currentStreak, 1)
    }

    func testNotDoneTodayOrYesterdayIsZero() {
        let habit = Habit(name: "x", doneDays: [dayKey(daysAgo: 2), dayKey(daysAgo: 3)])
        XCTAssertEqual(habit.currentStreak, 0)
    }

    func testHabitToggleReflectsToday() {
        var habit = Habit(name: "x")
        XCTAssertFalse(habit.isDone())
        habit.toggle()
        XCTAssertTrue(habit.isDone())
        habit.toggle()
        XCTAssertFalse(habit.isDone())
    }

    // MARK: - WidgetSnapshot.progress

    func testProgressIsZeroWhenNoTasks() {
        let snap = WidgetSnapshot(greeting: "", focusTitle: nil, doneTasks: 0,
                                  totalTasks: 0, habitsDone: 0, habitsTotal: 0, updated: Date())
        XCTAssertEqual(snap.progress, 0, "Avoids divide-by-zero when there are no tasks")
    }

    func testProgressIsFraction() {
        let snap = WidgetSnapshot(greeting: "", focusTitle: nil, doneTasks: 2,
                                  totalTasks: 4, habitsDone: 0, habitsTotal: 0, updated: Date())
        XCTAssertEqual(snap.progress, 0.5, accuracy: 0.0001)
    }

    // MARK: - Color(hex:)

    func testColorHexParsesValidStrings() {
        XCTAssertNotNil(Color(hex: "#FF8800"))
        XCTAssertNotNil(Color(hex: "FF8800"))
    }

    func testColorHexRejectsBadInput() {
        XCTAssertNil(Color(hex: nil))
        XCTAssertNil(Color(hex: "FFF"), "Three-digit shorthand isn't supported")
        XCTAssertNil(Color(hex: "nothex!"))
    }

    // MARK: - DayKey

    func testDayKeyFormat() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 23
        let date = Calendar.current.date(from: comps)!
        XCTAssertEqual(DayKey.string(for: date), "2026-06-23")
    }

    // MARK: - Theme.Daypart

    func testDaypartBoundaries() {
        XCTAssertEqual(Theme.Daypart.current(date(hour: 8)), .morning)
        XCTAssertEqual(Theme.Daypart.current(date(hour: 14)), .afternoon)
        XCTAssertEqual(Theme.Daypart.current(date(hour: 19)), .evening)
        XCTAssertEqual(Theme.Daypart.current(date(hour: 2)), .night)
    }

    func testGreetingMatchesDaypart() {
        XCTAssertEqual(Theme.greeting(for: date(hour: 8)), "Good morning")
        XCTAssertEqual(Theme.greeting(for: date(hour: 14)), "Good afternoon")
        XCTAssertEqual(Theme.greeting(for: date(hour: 19)), "Good evening")
    }
}
