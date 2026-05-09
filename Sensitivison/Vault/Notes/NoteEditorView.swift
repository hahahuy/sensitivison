import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cryptoVault: CryptoVault

    let note: VaultNote?

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var isDirty = false
    @State private var showDiscardAlert = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Title", text: $title)
                    .font(.title2.weight(.semibold))
                    .padding([.horizontal, .top])
                    .accessibilityLabel("Note title")
                    .onChange(of: title) { isDirty = true }
                Divider().padding(.top, 8)
                TextEditor(text: $bodyText)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .accessibilityLabel("Note body")
                    .onChange(of: bodyText) { isDirty = true }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { handleCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save(); dismiss() }
                        .disabled(!isDirty)
                        .fontWeight(.semibold)
                }
            }
            .alert("Save changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Save") { save(); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear(perform: loadNote)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && isDirty { save() }
        }
    }

    private func loadNote() {
        guard let note else { return }
        title = (try? cryptoVault.decryptString(note.encryptedTitle)) ?? ""
        bodyText = (try? cryptoVault.decryptString(note.encryptedBody)) ?? ""
    }

    private func handleCancel() {
        if isDirty { showDiscardAlert = true } else { dismiss() }
    }

    private func save() {
        guard let titleData = try? cryptoVault.encryptString(title.isEmpty ? "Untitled" : title),
              let bodyData = try? cryptoVault.encryptString(bodyText) else { return }
        if let note {
            note.encryptedTitle = titleData
            note.encryptedBody = bodyData
            note.updatedAt = .now
        } else {
            let newNote = VaultNote(encryptedTitle: titleData, encryptedBody: bodyData)
            modelContext.insert(newNote)
        }
        isDirty = false
    }
}
