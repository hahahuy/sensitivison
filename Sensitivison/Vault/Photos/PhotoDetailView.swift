import SwiftUI
import SwiftData
import UIKit

struct PhotoDetailView: View {
    let photo: VaultPhoto
    let vault: CryptoVault
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var showDeleteAlert = false
    @State private var barsVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .accessibilityLabel("Photo added \(photo.createdAt.formatted())")
            } else {
                ProgressView().tint(.white)
            }
        }
        .navigationBarHidden(!barsVisible)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showDeleteAlert = true } label: {
                    Image(systemName: "trash").tint(.red)
                }
                .accessibilityLabel("Delete photo")
            }
        }
        .alert("Delete photo?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteAndDismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
        .onTapGesture { withAnimation { barsVisible.toggle() } }
        .onAppear { Task { await decryptFullImage() } }
    }

    private func decryptFullImage() async {
        guard let data = FileManager.default.contents(atPath: photo.encryptedFilePath),
              let decrypted = try? vault.decrypt(data) else { return }
        await MainActor.run { image = UIImage(data: decrypted) }
    }

    private func deleteAndDismiss() {
        try? FileManager.default.removeItem(atPath: photo.encryptedFilePath)
        modelContext.delete(photo)
        dismiss()
    }
}
