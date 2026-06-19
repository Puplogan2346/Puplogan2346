import SwiftUI

struct RootView: View {
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
    }
}
