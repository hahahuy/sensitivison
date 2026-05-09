import XCTest
import CryptoKit
@testable import Sensitivison

final class CryptoVaultTests: XCTestCase {
    var vault: CryptoVault!

    override func setUp() {
        vault = CryptoVault(key: SymmetricKey(size: .bits256))
    }

    func test_encrypt_decrypt_data_roundtrip() throws {
        let original = Data("hello vault".utf8)
        let encrypted = try vault.encrypt(original)
        XCTAssertNotEqual(encrypted, original)
        let decrypted = try vault.decrypt(encrypted)
        XCTAssertEqual(decrypted, original)
    }

    func test_encrypt_string_roundtrip() throws {
        let original = "top secret"
        let encrypted = try vault.encryptString(original)
        let decrypted = try vault.decryptString(encrypted)
        XCTAssertEqual(decrypted, original)
    }

    func test_different_encryptions_of_same_data_differ() throws {
        let data = Data("same".utf8)
        let enc1 = try vault.encrypt(data)
        let enc2 = try vault.encrypt(data)
        XCTAssertNotEqual(enc1, enc2, "AES-GCM nonce must be random each call")
    }

    func test_decrypt_with_wrong_key_throws() throws {
        let encrypted = try vault.encrypt(Data("secret".utf8))
        let wrongVault = CryptoVault(key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try wrongVault.decrypt(encrypted))
    }

    func test_decrypt_tampered_data_throws() throws {
        var encrypted = try vault.encrypt(Data("secret".utf8))
        encrypted[encrypted.endIndex - 1] ^= 0xFF
        XCTAssertThrowsError(try vault.decrypt(encrypted))
    }
}
