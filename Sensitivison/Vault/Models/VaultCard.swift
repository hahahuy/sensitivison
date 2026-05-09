import Foundation
import SwiftData

@Model
final class VaultCard {
    var id: UUID
    var encryptedNumber: Data
    var encryptedCVV: Data
    var encryptedPIN: Data
    var encryptedHolder: Data
    var encryptedExpiry: Data
    var cardType: String  // "visa" | "mastercard" | "other" — unencrypted, used for card art only

    init(id: UUID = UUID(),
         encryptedNumber: Data,
         encryptedCVV: Data,
         encryptedPIN: Data,
         encryptedHolder: Data,
         encryptedExpiry: Data,
         cardType: String) {
        self.id = id
        self.encryptedNumber = encryptedNumber
        self.encryptedCVV = encryptedCVV
        self.encryptedPIN = encryptedPIN
        self.encryptedHolder = encryptedHolder
        self.encryptedExpiry = encryptedExpiry
        self.cardType = cardType
    }
}
