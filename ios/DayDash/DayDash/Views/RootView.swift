import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showWelcome = false

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }

            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }

            HabitsView()
                .tabItem { Label("Habits", systemImage: "flame.fill") }

            BrainDumpView()
                .tabItem { Label("Brain Dump", systemImage: "brain.head.profile") }

            AssistantView()
                .tabItem { Label("Assistant", systemImage: "sparkles") }
        }
        .tint(Theme.terracotta)
        .onAppear {
            // UI tests pass -skipOnboarding so the welcome sheet never blocks the tab bar.
            guard !CommandLine.arguments.contains("-skipOnboarding") else { return }
            if !hasOnboarded && store.userName.isEmpty {
                showWelcome = true
            } else {
                hasOnboarded = true
            }
        }
        .sheet(isPresented: $showWelcome, onDismiss: { hasOnboarded = true }) {
            WelcomeView()
        }
    }
}
