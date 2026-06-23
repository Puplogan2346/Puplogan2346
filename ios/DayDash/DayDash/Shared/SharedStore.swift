import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App Group identifier shared between the app and its Home Screen widget.
/// Enable this exact group on BOTH targets in Xcode (Signing & Capabilities ▸ App Groups).
enum AppGroup {
    static let id = "group.co.daydash.app"
}

/// A tiny, widget-friendly snapshot of "today". Written by the app, read by the widget.
struct WidgetSnapshot: Codable {
    var greeting: String
    var focusTitle: String?
    var doneTasks: Int
    var totalTasks: Int
    var habitsDone: Int
    var habitsTotal: Int
    var updated: Date

    var progress: Double {
        totalTasks > 0 ? Double(doneTasks) / Double(totalTasks) : 0
    }

    static let placeholder = WidgetSnapshot(
        greeting: "Good morning",
        focusTitle: "Pick your one thing",
        doneTasks: 1, totalTasks: 4,
        habitsDone: 2, habitsTotal: 3,
        updated: Date()
    )
}

/// Reads/writes the widget snapshot in the shared App Group container.
///
/// Falls back to the app's own Application Support directory when the App Group capability
/// hasn't been enabled yet — so the app keeps working before the widget target is wired.
/// (The widget process can only read the snapshot once the App Group is enabled on both targets.)
enum SharedStore {
    private static let filename = "daydash-widget.json"

    private static var fileURL: URL? {
        containerDirectory?.appendingPathComponent(filename)
    }

    private static var containerDirectory: URL? {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let dir else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func read() -> WidgetSnapshot {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }

    // MARK: - Pending actions (Home Screen → app)
    //
    // The interactive widget can't mutate the app's task list directly (separate process,
    // different container). Instead it queues a tiny command here; the app drains it on
    // launch / foreground and applies it to the real data. Round-trips between the two
    // processes only once the App Group is enabled on both targets.

    private static let pendingFilename = "daydash-pending.json"

    private struct PendingActions: Codable {
        var completeFocus = false
    }

    private static var pendingURL: URL? {
        containerDirectory?.appendingPathComponent(pendingFilename)
    }

    private static func readPending() -> PendingActions {
        guard let url = pendingURL,
              let data = try? Data(contentsOf: url),
              let actions = try? JSONDecoder().decode(PendingActions.self, from: data) else {
            return PendingActions()
        }
        return actions
    }

    private static func writePending(_ actions: PendingActions) {
        guard let url = pendingURL, let data = try? JSONEncoder().encode(actions) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Queue "complete the focus task" (called by the widget's AppIntent).
    static func requestFocusCompletion() {
        var actions = readPending()
        actions.completeFocus = true
        writePending(actions)
    }

    /// Returns whether a focus-completion was queued, clearing it (called by the app).
    static func consumeFocusCompletion() -> Bool {
        var actions = readPending()
        guard actions.completeFocus else { return false }
        actions.completeFocus = false
        writePending(actions)
        return true
    }

    /// Optimistically reflect a focus completion in the snapshot so the widget updates the
    /// instant it's tapped, before the app re-syncs from its real data.
    static func completeFocusOptimistically() {
        var snap = read()
        snap.focusTitle = nil
        if snap.totalTasks > 0 { snap.doneTasks = min(snap.doneTasks + 1, snap.totalTasks) }
        write(snap)
    }
}
