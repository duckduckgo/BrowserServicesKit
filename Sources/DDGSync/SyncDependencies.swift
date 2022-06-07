
import Foundation
import BrowserServicesKit

public protocol SyncDependencies {

    var endpoints: Endpoints { get }
    var account: AccountManaging { get }
    var api: RemoteAPIRequestCreating { get }
    var secureStore: SecureStoring { get }
    var responseHandler: ResponseHandling { get }
    var crypter: Crypting { get }

    func createUpdatesSender(_ persistence: LocalDataPersisting) throws -> UpdatesSending
    func createUpdatesFetcher(_ persistence: LocalDataPersisting) throws -> UpdatesFetching

}

public protocol AccountManaging {

    func createAccount(deviceName: String) async throws -> SyncAccount

    func login(recoveryKey: Data, deviceName: String) async throws -> (account: SyncAccount, devices: [RegisteredDevice])

}

public struct SyncAccount {

    public let deviceId: String
    public let userId: String
    public let primaryKey: Data
    public let secretKey: Data
    public let token: String?

}

public struct RegisteredDevice {
    
    public let id: String
    public let name: String

}

public protocol SecureStoring {

    func persistAccount(_ account: SyncAccount) throws

    func account() throws -> SyncAccount?

    func removeAccount() throws
}

public protocol ResponseHandling {

    func handleUpdates(_ data: Data) async throws

}

public protocol UpdatesFetching {

    func fetch() async throws

}

public protocol Crypting {

    func encryptAndBase64Encode(_ value: String) throws -> String

    func base64DecodeAndDecrypt(_ value: String) throws -> String

    func createAccountCreationKeys(userId: String, password: String) throws ->
        (primaryKey: Data, secretKey: Data, protectedSecretKey: Data, passwordHash: Data)

    func extractLoginInfo(recoveryKey: Data) throws ->
        (userId: String, primaryKey: Data, passwordHash: Data, stretchedPrimaryKey: Data)

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data

}

extension SyncAccount: Codable { // TODO does this make codable part public?
    
}
