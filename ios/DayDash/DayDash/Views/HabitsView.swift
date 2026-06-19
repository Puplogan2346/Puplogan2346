import SwiftUI

struct HabitsView: View {
    @Environment(AppStore.self) private var store
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var newEmoji = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.habits) { habit in
                    HStack(spacing: 12) {
                        Button {
                            withAnimation { store.toggleHabit(habit) }
                            Haptics.tap()
                        } label: {
                            Text(habit.emoji)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(
                                    habit.isDone() ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name).font(.body.weight(.medium))
                            Text(habit.currentStreak > 0
                                 ? "🔥 \(habit.currentStreak)-day streak"
                                 : "Tap to start a streak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if habit.isDone() {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                .onDelete { store.deleteHabits(at: $0) }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if store.habits.isEmpty {
                    ContentUnavailableView("No habits yet",
                                           systemImage: "flame",
                                           description: Text("Tap + to add a daily habit and build a streak."))
                }
            }
            .sheet(isPresented: $showingAdd) { addSheet }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                TextField("Habit name (e.g. Drink water)", text: $newName)
                TextField("Emoji", text: $newEmoji)
                    .onChange(of: newEmoji) { _, value in
                        if value.count > 2 { newEmoji = String(value.prefix(2)) }
                    }
            }
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { reset() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addHabit(name: newName, emoji: newEmoji)
                        reset()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func reset() {
        newName = ""; newEmoji = ""; showingAdd = false
    }
}
