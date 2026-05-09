import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit

struct DocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cryptoVault: CryptoVault
    @Query(sort: \VaultDocument.createdAt, order: .reverse) private var documents: [VaultDocument]
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    ContentUnavailableView("No documents yet",
                        systemImage: "doc.fill",
                        description: Text("Tap + to import a PDF"))
                } else {
                    List {
                        ForEach(documents) { doc in
                            NavigationLink(destination: PDFViewerView(document: doc, vault: cryptoVault)) {
                                DocRow(document: doc, vault: cryptoVault)
                            }
                        }
                        .onDelete(perform: deleteDocs)
                    }
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { isImporting = true }) { Image(systemName: "plus") }
                        .accessibilityLabel("Import PDF")
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf]) { result in
                Task { await importDocument(result) }
            }
        }
    }

    private func importDocument(_ result: Result<URL, Error>) async {
        guard let url = try? result.get(),
              url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url),
              let encrypted = try? cryptoVault.encrypt(data),
              let encName = try? cryptoVault.encryptString(url.deletingPathExtension().lastPathComponent) else { return }
        let pageCount = PDFDocument(data: data)?.pageCount ?? 0
        let fileURL = vaultDirectory().appendingPathComponent("\(UUID().uuidString).enc")
        try? encrypted.write(to: fileURL)
        let doc = VaultDocument(encryptedName: encName, encryptedFilePath: fileURL.path, pageCount: pageCount)
        await MainActor.run { modelContext.insert(doc) }
    }

    private func deleteDocs(at offsets: IndexSet) {
        for index in offsets {
            let doc = documents[index]
            try? FileManager.default.removeItem(atPath: doc.encryptedFilePath)
            modelContext.delete(doc)
        }
    }

    private func vaultDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vault/docs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private struct DocRow: View {
    let document: VaultDocument
    let vault: CryptoVault
    var name: String { (try? vault.decryptString(document.encryptedName)) ?? "Document" }
    var body: some View {
        HStack {
            Image(systemName: "doc.fill").foregroundStyle(.red)
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text("\(document.pageCount) pages").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(name), \(document.pageCount) pages")
    }
}
