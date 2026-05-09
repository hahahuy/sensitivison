import Foundation
import SwiftData

@Model
final class VaultNote {
    var id: UUID
    var encryptedTitle: Data
    var encryptedBody: Data
    var updatedAt: Date

    init(id: UUID = UUID(), encryptedTitle: Data, encryptedBody: Data, updatedAt: Date = .now) {
        self.id = id
        self.encryptedTitle = encryptedTitle
        self.encryptedBody = encryptedBody
        self.updatedAt = updatedAt
    }
}
