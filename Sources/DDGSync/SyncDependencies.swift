
import Foundation
import BrowserServicesKit

public protocol SyncDependencies {

    var account: AccountManaging { get }
    var api: RemoteAPIRequestCreating { get }
    var secureStore: SecureStoring { get }
    var dataLastUpdated: DataLastUpdatedPersisting { get }
    var responseHandler: ResponseHandling { get }
    var crypter: Crypting { get }

    func createAtomicSender() throws -> AtomicSending
    func createUpdatesFetcher() throws -> UpdatesFetching

}

public protocol AccountManaging {

    func createAccount(device: DeviceDetails) async throws -> SyncAccount

    func login(recoveryKey: Data, device: DeviceDetails) async throws -> SyncAccount

}

public struct SyncAccount {

    public let userId: String
    public let primaryKey: Data
    public let secretKey: Data
    public let token: String?
    public let baseDataUrl: URL

}

public protocol SecureStoring {

    func persistAccount(_ account: SyncAccount) throws

    func account() throws -> SyncAccount?

}

public protocol ResponseHandling {

    func handleUpdates(_ updates: [String: Any]) async throws

}

public protocol UpdatesFetching {

    func fetch() async throws

}

public protocol DataLastUpdatedPersisting {

    var bookmarks: String? { get }

    func bookmarksUpdated(_ lastUpdated: String)

    func reset()

}

public protocol Crypting {

    func encryptAndBase64Encode(_ value: String) throws -> String

    func base64DecodeAndDecrypt(_ value: String) throws -> String

    func createAccountCreationKeys(userId: String, password: String) throws ->
        (primaryKey: Data, secretKey: Data, protectedSymmetricKey: Data, passwordHash: Data)

    func extractLoginInfo(recoveryKey: Data) throws ->
        (userId: String, primaryKey: Data, passwordHash: Data, stretchedPrimaryKey: Data)

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data

}

extension SyncAccount: Codable { // TODO does this make codable part public?
    
}
