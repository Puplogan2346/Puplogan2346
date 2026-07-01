import SwiftUI

struct TasksView: View {
    @Environment(AppStore.self) private var store
    @State private var newTask = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                List {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.terracotta)
                            TextField("Add a task…", text: $newTask)
                                .font(Theme.rounded(.body))
                                .focused($addFocused)
                                .submitLabel(.done)
                                .onSubmit(add)
                        }
                    }

                    if !store.openTasks.isEmpty {
                        Section {
                            ForEach(store.openTasks) { task in row(task) }
                                .onDelete { store.deleteTasks(at: $0, in: store.openTasks) }
                        } header: {
                            Text("To do").font(Theme.rounded(.footnote, weight: .semibold))
                        }
                    }

                    let done = store.tasks.filter { $0.isDone }
                    if !done.isEmpty {
                        Section {
                            ForEach(done) { task in row(task) }
                                .onDelete { store.deleteTasks(at: $0, in: done) }
                        } header: {
                            Text("Done").font(Theme.rounded(.footnote, weight: .semibold))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .overlay {
                    if store.tasks.isEmpty {
                        ContentUnavailableView("No tasks yet",
                                               systemImage: "checklist",
                                               description: Text("Add your first task above."))
                    }
                }
            }
            .navigationTitle("Tasks")
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { store.toggleTask(task) }
                if !task.isDone { Haptics.success() } else { Haptics.tap() }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isDone ? .green : Color.secondary)
                    .symbolEffect(.bounce, value: task.isDone)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(Theme.rounded(.body))
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? .secondary : .primary)

            Spacer()

            if !task.isDone {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        store.setFocus(store.focusedTaskID == task.id ? nil : task.id)
                    }
                    Haptics.selection()
                } label: {
                    Image(systemName: "scope")
                        .foregroundStyle(store.focusedTaskID == task.id ? Theme.terracotta : Color.secondary.opacity(0.5))
                        .symbolEffect(.bounce, value: store.focusedTaskID == task.id)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focus on this task")
            }
        }
        .padding(.vertical, 2)
    }

    private func add() {
        guard !newTask.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { store.addTask(newTask) }
        newTask = ""
        Haptics.success()
    }
}
