import SwiftUI

/// A frictionless place to offload whatever's rattling around — no structure required.
struct BrainDumpView: View {
    @Environment(AppStore.self) private var store
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Dump a thought…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(10)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onSubmit(save)
                    Button(action: save) {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()

                List {
                    ForEach(store.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.text)
                            Text(note.createdAt, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { store.deleteNotes(at: $0) }
                }
                .listStyle(.plain)
                .overlay {
                    if store.notes.isEmpty {
                        ContentUnavailableView("Clear your head",
                                               systemImage: "brain.head.profile",
                                               description: Text("Type anything above — ideas, worries, reminders. Sort it out later."))
                    }
                }
            }
            .navigationTitle("Brain Dump")
        }
    }

    private func save() {
        store.addNote(draft)
        draft = ""
        Haptics.tap()
    }
}
