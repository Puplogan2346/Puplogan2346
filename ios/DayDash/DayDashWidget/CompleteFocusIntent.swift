import AppIntents

/// Interactive widget button: completes today's focus task straight from the Home Screen.
///
/// The widget runs in its own process and can't touch the app's task store, so this queues
/// a command via `SharedStore` (which the app drains on next launch/foreground) and updates
/// the shared snapshot optimistically so the widget reflects the tap immediately.
///
/// NOTE: lives in the widget target. `SharedStore.swift` must be a member of this target too
/// (see DayDashWidget-SETUP.md), and the round-trip back into the app requires the App Group
/// enabled on both targets.
struct CompleteFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete focus task"
    static var description = IntentDescription("Marks today's focus task as done.")

    func perform() async throws -> some IntentResult {
        SharedStore.requestFocusCompletion()
        SharedStore.completeFocusOptimistically()
        return .result()
    }
}
