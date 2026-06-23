import XCTest
@testable import DayDash

/// Tests for `AppStore` mutations. `AppStore` persists to disk, so these tests use uniquely
/// prefixed titles and clean up after themselves — they assert only about the items they
/// create, which makes them robust to any pre-existing (sample or persisted) state.
final class AppStoreTests: XCTestCase {

    private let prefix = "ZZTEST-"

    override func tearDown() {
        // Remove anything this test file created so runs don't accumulate on disk.
        let store = AppStore()
        let mine = store.tasks.enumerated()
            .filter { $0.element.title.hasPrefix(prefix) }
            .map { $0.offset }
        if !mine.isEmpty {
            store.deleteTasks(at: IndexSet(mine), in: store.tasks)
        }
        super.tearDown()
    }

    func testAddTaskInsertsAtTopAndShowsAsOpen() {
        let store = AppStore()
        store.addTask("\(prefix)alpha")
        XCTAssertEqual(store.openTasks.first?.title, "\(prefix)alpha")
    }

    func testAddTaskIgnoresWhitespaceOnly() {
        let store = AppStore()
        let before = store.tasks.count
        store.addTask("   \n ")
        XCTAssertEqual(store.tasks.count, before, "Blank titles should not create tasks")
    }

    func testCompletingFocusedTaskClearsFocus() {
        let store = AppStore()
        store.addTask("\(prefix)focusme")
        guard let task = store.tasks.first(where: { $0.title == "\(prefix)focusme" }) else {
            return XCTFail("task not found")
        }
        store.setFocus(task.id)
        XCTAssertEqual(store.focusedTask?.id, task.id)

        store.toggleTask(task)
        XCTAssertNil(store.focusedTask, "Marking the focused task done should drop the focus")
    }

    /// The important property of `deleteTasks(at:in:)`: offsets are interpreted against the
    /// *filtered* list shown in the UI, then mapped to ids before deleting from the full list.
    /// This must delete the right task even when the visible list differs from `tasks`.
    func testDeleteFromFilteredListMapsOffsetsCorrectly() {
        let store = AppStore()
        store.addTask("\(prefix)A")
        store.addTask("\(prefix)B")
        store.addTask("\(prefix)C")

        // Complete B so `openTasks` no longer lines up index-for-index with `tasks`.
        if let b = store.tasks.first(where: { $0.title == "\(prefix)B" }) {
            store.toggleTask(b)
        }

        let open = store.openTasks
        guard let idxOfC = open.firstIndex(where: { $0.title == "\(prefix)C" }) else {
            return XCTFail("C should be open")
        }

        store.deleteTasks(at: IndexSet(integer: idxOfC), in: open)

        XCTAssertFalse(store.tasks.contains { $0.title == "\(prefix)C" }, "C should be deleted")
        XCTAssertTrue(store.tasks.contains { $0.title == "\(prefix)A" }, "A should remain")
        XCTAssertTrue(store.tasks.contains { $0.title == "\(prefix)B" }, "B (done) should remain")
    }
}
