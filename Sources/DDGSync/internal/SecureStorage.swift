
import Foundation

struct SecureStorage: SecureStoring {

    func persistAccount(_ account: SyncAccount) throws {
        // TODO save to keychain

        print("UserId", account.userId)
        print("Token", account.token)
        print("SecretKey", account.secretKey.base64EncodedString())
        print("PrimaryKey", account.primaryKey.base64EncodedString())

    }

}
