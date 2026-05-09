import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct PhotosView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cryptoVault: CryptoVault
    @Query(sort: \VaultPhoto.createdAt, order: .reverse) private var photos: [VaultPhoto]
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    ContentUnavailableView("No photos yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Tap + to import from your Camera Roll"))
                } else {
                    PhotoGridView(photos: photos, vault: cryptoVault)
                }
            }
            .navigationTitle("Photos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import photo")
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                Task { await importPhotos(newItems) }
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let encrypted = try? cryptoVault.encrypt(data) else { continue }
            let fileURL = vaultDirectory().appendingPathComponent("\(UUID().uuidString).enc")
            try? encrypted.write(to: fileURL)
            let thumbnail = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 120, height: 120))
            let thumbData = thumbnail?.jpegData(compressionQuality: 0.7) ?? Data()
            let encThumb = (try? cryptoVault.encrypt(thumbData)) ?? Data()
            let photo = VaultPhoto(encryptedFilePath: fileURL.path, encryptedThumbnail: encThumb)
            await MainActor.run { modelContext.insert(photo) }
        }
        await MainActor.run { pickerItems = [] }
    }

    private func vaultDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vault/photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
