import SwiftUI

struct TasksView: View {
    @Environment(AppStore.self) private var store
    @State private var newTask = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add a task…", text: $newTask)
                            .onSubmit(add)
                        Button(action: add) { Image(systemName: "plus.circle.fill") }
                            .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !store.openTasks.isEmpty {
                    Section("To do") {
                        ForEach(store.openTasks) { task in
                            row(task)
                        }
                        .onDelete { store.deleteTasks(at: $0, in: store.openTasks) }
                    }
                }

                let done = store.tasks.filter { $0.isDone }
                if !done.isEmpty {
                    Section("Done") {
                        ForEach(done) { task in row(task) }
                            .onDelete { store.deleteTasks(at: $0, in: done) }
                    }
                }
            }
            .navigationTitle("Tasks")
            .overlay {
                if store.tasks.isEmpty {
                    ContentUnavailableView("No tasks yet",
                                           systemImage: "checklist",
                                           description: Text("Add your first task above."))
                }
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { store.toggleTask(task) }
                if !task.isDone { Haptics.success() }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? .secondary : .primary)

            Spacer()

            if !task.isDone {
                Button {
                    withAnimation {
                        store.setFocus(store.focusedTaskID == task.id ? nil : task.id)
                    }
                } label: {
                    Image(systemName: "scope")
                        .foregroundStyle(store.focusedTaskID == task.id ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focus on this task")
            }
        }
    }

    private func add() {
        store.addTask(newTask)
        newTask = ""
        Haptics.tap()
    }
}
