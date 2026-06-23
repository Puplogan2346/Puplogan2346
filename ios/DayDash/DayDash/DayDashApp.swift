import SwiftUI

@main
struct DayDashApp: App {
    // One shared store for the whole app. @State keeps the @Observable instance alive.
    @State private var store = AppStore()
    // One shared Claude service so the API-key state stays consistent across every tab and sheet.
    @State private var claude = ClaudeService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(claude)
                .tint(.accentColor)
        }
    }
}
