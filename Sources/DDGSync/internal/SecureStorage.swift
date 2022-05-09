
import Foundation

// TODO use a struct if possible
class SecureStorage: SecureStoring {

    private var _account: SyncAccount?

    func persistAccount(_ account: SyncAccount) throws {
        self._account = account

        // TODO save to keychain

        print("UserId", account.userId)
        print("Token", account.token)
        print("SecretKey", account.secretKey.base64EncodedString())
        print("PrimaryKey", account.primaryKey.base64EncodedString())

    }

    func account() throws -> SyncAccount {
        guard let account = _account else {
            throw SyncError.accountNotFound
        }

        return account
    }

}
