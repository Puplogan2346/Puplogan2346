import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// Self-contained copy of the shared snapshot types for the widget target.
// (The app target has its own copy in DayDash/Shared/SharedStore.swift. Same type
// names in two separate targets is fine — they compile into separate binaries.)

/// App Group identifier shared between the app and this widget.
/// Enable this exact group on BOTH targets in Xcode (Signing & Capabilities ▸ App Groups)
/// to show live data; until then the widget shows placeholder content.
enum AppGroup {
    static let id = "group.co.daydash.app"
}

struct WidgetSnapshot: Codable {
    var greeting: String
    var focusTitle: String?
    var doneTasks: Int
    var totalTasks: Int
    var habitsDone: Int
    var habitsTotal: Int
    var updated: Date

    var progress: Double { totalTasks > 0 ? Double(doneTasks) / Double(totalTasks) : 0 }

    static let placeholder = WidgetSnapshot(
        greeting: "Good morning",
        focusTitle: "Pick your one thing",
        doneTasks: 1, totalTasks: 4,
        habitsDone: 2, habitsTotal: 3,
        updated: Date()
    )
}

enum SharedStore {
    private static let filename = "daydash-widget.json"

    private static var fileURL: URL? {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let dir else { return nil }
        return dir.appendingPathComponent(filename)
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
