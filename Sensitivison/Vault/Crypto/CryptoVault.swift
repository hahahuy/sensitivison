import Foundation
import CryptoKit
import Combine

final class CryptoVault: ObservableObject {
    private var key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    func encrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CryptoVaultError.encryptionFailed
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    func encryptString(_ string: String) throws -> Data {
        guard let data = string.data(using: .utf8) else {
            throw CryptoVaultError.invalidString
        }
        return try encrypt(data)
    }

    func decryptString(_ data: Data) throws -> String {
        let decrypted = try decrypt(data)
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw CryptoVaultError.invalidString
        }
        return string
    }

    func lock() {
        key = SymmetricKey(size: .bits256)
    }
}

enum CryptoVaultError: Error {
    case encryptionFailed
    case invalidString
}
