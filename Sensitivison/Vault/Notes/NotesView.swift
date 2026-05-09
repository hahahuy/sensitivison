import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cryptoVault: CryptoVault
    @Query(sort: \VaultNote.updatedAt, order: .reverse) private var notes: [VaultNote]
    @State private var isAddingNote = false

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    ContentUnavailableView("No notes yet",
                        systemImage: "note.text",
                        description: Text("Tap + to create your first note"))
                } else {
                    List {
                        ForEach(notes) { note in
                            NavigationLink(destination: NoteEditorView(note: note)) {
                                NoteRow(note: note, vault: cryptoVault)
                            }
                        }
                        .onDelete(perform: deleteNotes)
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { isAddingNote = true }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New note")
                }
            }
            .navigationDestination(isPresented: $isAddingNote) {
                NoteEditorView(note: nil)
            }
        }
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = notes[index]
            modelContext.delete(note)
        }
    }
}

private struct NoteRow: View {
    let note: VaultNote
    let vault: CryptoVault
    var decryptedTitle: String { (try? vault.decryptString(note.encryptedTitle)) ?? "Untitled" }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(decryptedTitle).font(.headline)
            Text(note.updatedAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(decryptedTitle), updated \(note.updatedAt.formatted(.relative(presentation: .named)))")
    }
}
