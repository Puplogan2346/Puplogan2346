import SwiftUI

/// A frictionless place to offload whatever's rattling around — no structure required.
struct BrainDumpView: View {
    @Environment(AppStore.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    List {
                        ForEach(store.notes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.text).font(Theme.rounded(.body))
                                Text(note.createdAt, format: .relative(presentation: .named))
                                    .font(Theme.rounded(.caption2))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        store.makeTask(from: note)
                                    }
                                    Haptics.success()
                                } label: {
                                    Label("Make task", systemImage: "checklist")
                                }
                                .tint(Theme.terracotta)
                            }
                        }
                        .onDelete { store.deleteNotes(at: $0) }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                    .overlay {
                        if store.notes.isEmpty {
                            ContentUnavailableView("Clear your head",
                                                   systemImage: "brain.head.profile",
                                                   description: Text("Type anything below — ideas, worries, reminders. Swipe a thought right later to turn it into a task."))
                        }
                    }

                    composer
                }
            }
            .navigationTitle("Brain Dump")
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Dump a thought…", text: $draft, axis: .vertical)
                .font(Theme.rounded(.body))
                .lineLimit(1...4)
                .focused($focused)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
            Button(action: save) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white, Theme.terracotta)
            }
            .buttonStyle(.pressable)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(.thinMaterial)
    }

    private func save() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { store.addNote(draft) }
        draft = ""
        Haptics.success()
    }
}
