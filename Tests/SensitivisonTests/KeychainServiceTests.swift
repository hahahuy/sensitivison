import XCTest
@testable import Sensitivison

final class KeychainServiceTests: XCTestCase {
    let key = "test.keychain.key.\(UUID().uuidString)"

    override func tearDown() {
        try? KeychainService.delete(key: key)
    }

    func test_save_and_load_roundtrip() throws {
        let data = Data("secret".utf8)
        try KeychainService.save(data: data, key: key)
        let loaded = try KeychainService.load(key: key)
        XCTAssertEqual(loaded, data)
    }

    func test_load_missing_key_throws() {
        XCTAssertThrowsError(try KeychainService.load(key: key)) { error in
            XCTAssertEqual(error as? KeychainService.KeychainError, .itemNotFound)
        }
    }

    func test_overwrite_existing_key() throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        try KeychainService.save(data: first, key: key)
        try KeychainService.save(data: second, key: key)
        let loaded = try KeychainService.load(key: key)
        XCTAssertEqual(loaded, second)
    }

    func test_delete_removes_item() throws {
        try KeychainService.save(data: Data("x".utf8), key: key)
        try KeychainService.delete(key: key)
        XCTAssertThrowsError(try KeychainService.load(key: key))
    }
}
