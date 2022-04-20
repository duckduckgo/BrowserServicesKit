
import XCTest
import DDGSyncAuth

class DDGSyncAuthTests: XCTestCase {

    func testCreateAccount() {
        let primaryKey = UnsafeMutablePointer<CChar>.allocate(capacity: Int(DDGSYNCAUTH_PRIMARY_KEY_SIZE))
        let protectedSymmetricKey = UnsafeMutablePointer<CChar>.allocate(capacity: Int(DDGSYNCAUTH_PROTECTED_SYMMETRIC_KEY_SIZE))
        let passwordHash = UnsafeMutablePointer<CChar>.allocate(capacity: Int(DDGSYNCAUTH_HASH_SIZE))

        XCTAssertTrue(String(cString: primaryKey).isEmpty)
        XCTAssertTrue(String(cString: protectedSymmetricKey).isEmpty)
        XCTAssertTrue(String(cString: passwordHash).isEmpty)

        XCTAssertEqual(DDGSYNCAUTH_OK, ddgSyncCreateAccount(primaryKey, protectedSymmetricKey, passwordHash, "UserID", "Password"))

        XCTAssertFalse(String(cString: primaryKey).isEmpty)
        XCTAssertFalse(String(cString: protectedSymmetricKey).isEmpty)
        XCTAssertFalse(String(cString: passwordHash).isEmpty)
    }

}
