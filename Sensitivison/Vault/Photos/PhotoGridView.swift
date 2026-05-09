import SwiftUI
import SwiftData
import UIKit

struct PhotoGridView: View {
    let photos: [VaultPhoto]
    let vault: CryptoVault
    @Environment(\.modelContext) private var modelContext
    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(photos) { photo in
                    NavigationLink(destination: PhotoDetailView(photo: photo, vault: vault)) {
                        ThumbnailCell(photo: photo, vault: vault)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) { delete(photo) }
                    }
                }
            }
        }
    }

    private func delete(_ photo: VaultPhoto) {
        try? FileManager.default.removeItem(atPath: photo.encryptedFilePath)
        modelContext.delete(photo)
    }
}

private struct ThumbnailCell: View {
    let photo: VaultPhoto
    let vault: CryptoVault
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fill).clipped()
        .onAppear { Task { await decrypt() } }
        .accessibilityLabel("Photo, added \(photo.createdAt.formatted(.relative(presentation: .named)))")
    }

    private func decrypt() async {
        guard let decrypted = try? vault.decrypt(photo.encryptedThumbnail) else { return }
        await MainActor.run { image = UIImage(data: decrypted) }
    }
}
