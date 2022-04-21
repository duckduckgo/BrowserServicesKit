
import XCTest
import DDGSyncAuth
import Clibsodium

class DDGSyncAuthTests: XCTestCase {

    func testCreateAccount() {
        var primaryKey = [UInt8](repeating: 0, count: Int(DDGSYNCAUTH_PRIMARY_KEY_SIZE.rawValue))
        var protectedSymmetricKey = [UInt8](repeating: 0, count: Int(DDGSYNCAUTH_PROTECTED_SYMMETRIC_KEY_SIZE.rawValue))
        var passwordHash = [UInt8](repeating: 0, count: Int(DDGSYNCAUTH_HASH_SIZE.rawValue))

        XCTAssertEqual(DDGSYNCAUTH_OK, ddgSyncCreateAccount(&primaryKey, &protectedSymmetricKey, &passwordHash, "UserID", "Password"))
    }

}
