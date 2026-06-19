import SwiftUI

struct HabitsView: View {
    @Environment(AppStore.self) private var store
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var newEmoji = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                List {
                    ForEach(store.habits) { habit in
                        HStack(spacing: 14) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { store.toggleHabit(habit) }
                                Haptics.soft()
                            } label: {
                                Text(habit.emoji)
                                    .font(.title2)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        habit.isDone() ? Theme.terracotta.opacity(0.18) : Color.primary.opacity(0.06),
                                        in: Circle()
                                    )
                                    .overlay(Circle().strokeBorder(habit.isDone() ? Theme.terracotta.opacity(0.45) : .clear, lineWidth: 1.5))
                                    .symbolEffect(.bounce, value: habit.isDone())
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.name).font(Theme.rounded(.body, weight: .medium))
                                Text(habit.currentStreak > 0
                                     ? "🔥 \(habit.currentStreak)-day streak"
                                     : "Tap to start a streak")
                                    .font(Theme.rounded(.caption))
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }

                            Spacer()

                            if habit.isDone() {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { store.deleteHabits(at: $0) }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .overlay {
                    if store.habits.isEmpty {
                        ContentUnavailableView("No habits yet",
                                               systemImage: "flame",
                                               description: Text("Tap + to add a daily habit and build a streak."))
                    }
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.tap(); showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) { addSheet }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("Name (e.g. Drink water)", text: $newName)
                        .font(Theme.rounded(.body))
                }
                Section("Icon") {
                    HStack {
                        TextField("Emoji", text: $newEmoji)
                            .onChange(of: newEmoji) { _, value in
                                if value.count > 2 { newEmoji = String(value.prefix(2)) }
                            }
                        Spacer()
                        Text(newEmoji.isEmpty ? "✅" : newEmoji).font(.title)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(["💧","🏃","📚","🧘","🥗","😴","☀️","✍️","🎧","🌱"], id: \.self) { e in
                                Button { newEmoji = e; Haptics.selection() } label: {
                                    Text(e).font(.title2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
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
                        withAnimation { store.addHabit(name: newName, emoji: newEmoji) }
                        Haptics.success()
                        reset()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func reset() {
        newName = ""; newEmoji = ""; showingAdd = false
    }
}
