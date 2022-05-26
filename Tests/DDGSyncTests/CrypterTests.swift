
import Clibsodium
import XCTest
import DDGSyncCrypto
@testable import DDGSync

class CrypterTests: XCTestCase {

    func testWhenGivenRecoveryKeyThenCanExtractSecretKey() throws {
        let mockStorage = MockStorage()
        let crypter = Crypter(secureStore: mockStorage)

        let userId = "Simple User Name"
        
        let account = try crypter.createAccountCreationKeys(userId: userId, password: "password")
        let login = try crypter.extractLoginInfo(recoveryKey: account.primaryKey + userId.data(using: .utf8)!)
        XCTAssertEqual(account.passwordHash, login.passwordHash)

        // The login flow calls the server to retreve the protected secret key, but we already have it so check we can decrypt it.
        
        let secretKey = try crypter.extractSecretKey(protectedSecretKey: account.protectedSymmetricKey, stretchedPrimaryKey: login.stretchedPrimaryKey)
        XCTAssertEqual(account.secretKey, secretKey)
    }
    
    func testWhenGivenRecoveryKeyThenCanExtractUserIdAndPrimaryKey() throws {
        let mockStorage = MockStorage()
        let crypter = Crypter(secureStore: mockStorage)
        
        let userId = "Simple User Name"
        let primaryKey = Data([UInt8](repeating: 1, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue)))
        
        let recoveryKey = primaryKey + userId.data(using: .utf8)!
        let loginInfo = try crypter.extractLoginInfo(recoveryKey: recoveryKey)
        
        XCTAssertEqual(loginInfo.userId, userId)
        XCTAssertEqual(loginInfo.primaryKey, primaryKey)
    }
    
    func testWhenDecryptingNoneBase64ThenErrorIsThrown() throws {
        let mockStorage = MockStorage()
        let primaryKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        let secretKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        try mockStorage.persistAccount(SyncAccount(userId: "userId",
                                                   primaryKey: primaryKey,
                                                   secretKey: secretKey,
                                                   token: "token",
                                                   baseDataUrl: URL(string: "https://sync-data.duckduckgo.com")!))
        let message = "😆 " + UUID().uuidString + " 🥴 " + UUID().uuidString

        let crypter = Crypter(secureStore: mockStorage)

        XCTAssertThrowsError(try crypter.base64DecodeAndDecrypt(message))
    }

    func testWhenEncryptingValueThenItIsBase64AndCanBeDecrypted() throws {
        let mockStorage = MockStorage()
        let primaryKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        let secretKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        try mockStorage.persistAccount(SyncAccount(userId: "userId",
                                                   primaryKey: primaryKey,
                                                   secretKey: secretKey,
                                                   token: "token",
                                                   baseDataUrl: URL(string: "https://sync-data.duckduckgo.com")!))
        let message = "😆 " + UUID().uuidString + " 🥴 " + UUID().uuidString

        let crypter = Crypter(secureStore: mockStorage)
        let encrypted = try crypter.encryptAndBase64Encode(message)
        XCTAssertNotEqual(encrypted, message)
        assertValidBase64(encrypted)

        let decrypted = try crypter.base64DecodeAndDecrypt(encrypted)
        XCTAssertEqual(decrypted, message)
    }

    func assertValidBase64(_ base64: String) {
        for c in base64 {
            XCTAssertTrue(c.isLetter || c.isNumber || ["+", "/", "="].contains(c), "\(c) not valid base64 char")
        }
    }

}
