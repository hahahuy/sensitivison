import Foundation
import SwiftData

@Model
final class VaultPhoto {
    var id: UUID
    var encryptedFilePath: String  // UUID-based filename — safe to store unencrypted
    var encryptedThumbnail: Data
    var createdAt: Date

    init(id: UUID = UUID(), encryptedFilePath: String, encryptedThumbnail: Data, createdAt: Date = .now) {
        self.id = id
        self.encryptedFilePath = encryptedFilePath
        self.encryptedThumbnail = encryptedThumbnail
        self.createdAt = createdAt
    }
}
