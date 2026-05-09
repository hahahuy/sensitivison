import Foundation
import SwiftData

@Model
final class VaultDocument {
    var id: UUID
    var encryptedName: Data
    var encryptedFilePath: String  // UUID-based filename — safe to store unencrypted
    var pageCount: Int
    var createdAt: Date

    init(id: UUID = UUID(), encryptedName: Data, encryptedFilePath: String, pageCount: Int, createdAt: Date = .now) {
        self.id = id
        self.encryptedName = encryptedName
        self.encryptedFilePath = encryptedFilePath
        self.pageCount = pageCount
        self.createdAt = createdAt
    }
}
