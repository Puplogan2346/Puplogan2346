import SwiftUI

@main
struct DayDashApp: App {
    // One shared store for the whole app. @State keeps the @Observable instance alive.
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(.accentColor)
        }
    }
}
