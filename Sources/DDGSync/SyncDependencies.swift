
import Foundation
import BrowserServicesKit

public protocol SyncDependencies {

    var account: AccountManaging { get }
    var api: RemoteAPIRequestCreating { get }
    var secureStore: SecureStoring { get }
    var responseHandler: ResponseHandling { get }
    var crypter: Crypting { get }

    func createAtomicSender(_ persistence: LocalDataPersisting) throws -> AtomicSending
    func createUpdatesFetcher(_ persistence: LocalDataPersisting) throws -> UpdatesFetching

}

public protocol AccountManaging {

    func createAccount(device: DeviceDetails) async throws -> SyncAccount

    func login(recoveryKey: Data, device: DeviceDetails) async throws -> (account: SyncAccount, devices: [RegisteredDevice])

}

public struct SyncAccount {

    public let userId: String
    public let primaryKey: Data
    public let secretKey: Data
    public let token: String?
    public let baseDataUrl: URL

}

public struct RegisteredDevice {
    
    public let id: String
    public let name: String

}

public protocol SecureStoring {

    func persistAccount(_ account: SyncAccount) throws

    func account() throws -> SyncAccount?

    func clearToken() throws 
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
