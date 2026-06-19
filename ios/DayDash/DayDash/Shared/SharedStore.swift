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
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let dir else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
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
}
