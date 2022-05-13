
import Foundation
import DDGSync

class MockStorage: SecureStoring {

    var _account: SyncAccount?

    func persistAccount(_ account: SyncAccount) throws {
        _account = account
    }

    func account() throws -> SyncAccount {
        guard let account = _account else {
            throw SyncError.accountNotFound
        }
        return account
    }

}
