
import Foundation
import BrowserServicesKit

public protocol SyncDependencies {

    var accountCreation: AccountCreating { get }
    var api: RemoteAPIRequestCreating { get }
    var keyGenerator: KeyGenerating { get }
    var secureStore: SecureStoring { get }
    var dataLastUpdated: DataLastUpdatedPersisting { get }
    var responseHandler: ResponseHandling { get }
    var crypter: Crypting { get }

    func createAtomicSender() throws -> AtomicSending
    func createUpdatesFetcher() throws -> UpdatesFetching

}

public protocol AccountCreating {

    func createAccount(device: DeviceDetails) async throws -> SyncAccount

}

public struct SyncAccount {

    let userId: String
    let primaryKey: Data
    let secretKey: Data
    let token: String
    let baseDataURL: URL

}

public protocol KeyGenerating {

    func createAccountCreationKeys(userId: String, password: String) throws -> AccountCreationKeys

}

public struct AccountCreationKeys {

    let primaryKey: [UInt8]
    let secretKey: [UInt8]
    let protectedSymmetricKey: [UInt8]
    let passwordHash: [UInt8]

}

public protocol SecureStoring {

    func persistAccount(_ account: SyncAccount) throws

    func account() throws -> SyncAccount

}

public protocol ResponseHandling {

    func handleUpdates(_ updates: [String: Any]) async throws

}

public protocol UpdatesFetching {

    func fetch() async throws

}

public protocol DataLastUpdatedPersisting {

    var bookmarks: String? { get }
    var favorites: String? { get }

    func bookmarksUpdated(_ lastUpdated: String)
    func favoritesUpdated(_ lastUpdated: String)

}

public protocol Crypting {

    func encryptAndBase64Encode(_ value: String) throws -> String

    func base64DecodeAndDecrypt(_ value: String) throws -> String

}
