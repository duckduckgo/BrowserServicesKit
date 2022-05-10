
import XCTest
import DDGSyncCrypto
import Clibsodium

class DDGSyncCryptoTests: XCTestCase {

    func testWhenGeneratingAccountKeysThenEachKeyIsValid() {
        var primaryKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))
        var secretKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
        var protectedSymmetricKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PROTECTED_SYMMETRIC_KEY_SIZE.rawValue))
        var passwordHash = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_HASH_SIZE.rawValue))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey,
                                                                  &secretKey,
                                                                  &protectedSymmetricKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        assertValidKey(primaryKey)
        assertValidKey(secretKey)
        assertValidKey(protectedSymmetricKey)
        assertValidKey(passwordHash)
    }

    func testWhenGeneratingAccountKeysThenPrimaryIsDeterministic() {
        var primaryKey1 = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))
        var primaryKey2 = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))
        var secretKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
        var protectedSymmetricKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PROTECTED_SYMMETRIC_KEY_SIZE.rawValue))
        var passwordHash = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_HASH_SIZE.rawValue))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey1,
                                                                  &secretKey,
                                                                  &protectedSymmetricKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey2,
                                                                  &secretKey,
                                                                  &protectedSymmetricKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        assertValidKey(primaryKey1)
        assertValidKey(primaryKey2)

        XCTAssertEqual(primaryKey1, primaryKey2)
    }

    func testWhenGeneratingAccountKeysThenSecretKeyIsNonDeterministic() {
        var primaryKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))
        var secretKey1 = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
        var secretKey2 = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
        var protectedSymmetricKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PROTECTED_SYMMETRIC_KEY_SIZE.rawValue))
        var passwordHash = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_HASH_SIZE.rawValue))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey,
                                                                  &secretKey1,
                                                                  &protectedSymmetricKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey,
                                                                  &secretKey2,
                                                                  &protectedSymmetricKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        // The chance of these being randomly the same is so low that it should never happen.
        XCTAssertNotEqual(secretKey1, secretKey2)
    }

    func assertValidKey(_ key: [UInt8]) {
        var nullCount = 0
        for value in key {
            if value == 0 {
                nullCount += 1
            }
        }
        XCTAssertNotEqual(nullCount, key.count)
    }

}
