
import XCTest
import DDGSyncAuth

class DDGSyncAuthTests: XCTestCase {

    func testCreateAccount() {
        var primaryKey = [UInt8](repeating: 0, count: Int(DDGSYNCAUTH_PRIMARY_KEY_SIZE))
        var protectedSymmetricKey = [UInt8](repeating: 0, count: Int(DDGSYNCAUTH_PROTECTED_SYMMETRIC_KEY_SIZE))
        var passwordHash = [UInt8](repeating: 0, count: Int(DDGSYNCAUTH_HASH_SIZE))

        XCTAssertEqual(DDGSYNCAUTH_OK, ddgSyncCreateAccount(&primaryKey, &protectedSymmetricKey, &passwordHash, "UserID", "Password"))

        assertValidKey(primaryKey)
        assertValidKey(protectedSymmetricKey)
        assertValidKey(passwordHash)
    }

    func assertValidKey(_ key: [UInt8], file: StaticString = #file, line: UInt = #line) {
        for i in 0 ..< key.count {
            XCTAssertNotEqual(0, key[i], "element \(i) is NULL", file: file, line: line)
        }
    }

}
