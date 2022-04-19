
import XCTest
import DDGSyncAuth

class DDGSyncAuthTests: XCTestCase {

    func testWhenGivenAKeyThenItGeneratesAHashWhichCanBeVerified() {
        let primaryKey = "Correct Horse Battery Staple"
        let hash = UnsafeMutablePointer<CChar>.allocate(capacity: Int(DDGSYNCAUTH_HASH_SIZE))
        XCTAssertEqual(DDGSYNCAUTH_OK, ddgSyncCreatePasswordHash(primaryKey, hash))
        print(String(cString: hash))
        XCTAssertEqual(0, crypto_pwhash_str_verify(hash, primaryKey, UInt64(primaryKey.count)))
    }

}
