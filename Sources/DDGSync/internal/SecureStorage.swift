
import Foundation

// TODO this stuff needs stored in the keychain
struct SecureStorage: SecureStoring {

    let accountFile = URL(fileURLWithPath: "account.json")

    func persistAccount(_ account: SyncAccount) throws {
        print("UserId", account.userId)
        print("Token", account.token ?? "<no token>")
        print("SecretKey", account.secretKey.base64EncodedString())
        print("PrimaryKey", account.primaryKey.base64EncodedString())

        try JSONEncoder().encode(account).write(to: accountFile, options: .atomic)
    }

    func account() throws -> SyncAccount? {
        guard let data = try? Data(contentsOf: accountFile) else { return nil }
        return try JSONDecoder().decode(SyncAccount.self, from: data)
    }

}
