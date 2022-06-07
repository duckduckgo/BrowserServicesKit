
import Foundation
import Combine

import DDGSyncCrypto

public class DDGSync: DDGSyncing {

    enum Constants {
        public static let baseUrl = URL(string: "https://sync.duckduckgo.com")!
    }

    public var isAuthenticated: Bool {
        return (try? dependencies.secureStore.account()?.token) != nil
    }

    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies

    init(persistence: LocalDataPersisting, dependencies: SyncDependencies) {
        self.persistence = persistence
        self.dependencies = dependencies
    }

    /// This is the constructor intended for use by app clients.
    public convenience init(persistence: LocalDataPersisting) {
        let dependencies = ProductionDependencies(baseUrl: Constants.baseUrl, persistence: persistence)
        self.init(persistence: persistence, dependencies: dependencies)
    }

    public convenience init(persistence: LocalDataPersisting,
                            fileStorageUrl: URL,
                            baseUrl: URL,
                            secureStore: SecureStoring) {
        
        let dependencies = ProductionDependencies(fileStorageUrl: fileStorageUrl,
                                                  baseUrl: baseUrl,
                                                  persistence: persistence,
                                                  secureStore: secureStore)
        
        self.init(persistence: persistence, dependencies: dependencies)
    }

    public func createAccount(deviceName: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let account = try await dependencies.account.createAccount(deviceName: deviceName)
        try dependencies.secureStore.persistAccount(account)
    }

    public func login(recoveryKey: Data, deviceName: String) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let result = try await dependencies.account.login(recoveryKey: recoveryKey, deviceName: deviceName)
        try dependencies.secureStore.persistAccount(result.account)
        try await persistence.persistDevices(result.devices)
    }

    public func sender() throws -> UpdatesSending {
        return try dependencies.createUpdatesSender(persistence)
    }

    public func fetchLatest() async throws {
        try await dependencies.createUpdatesFetcher(persistence).fetch()
    }

    public func fetchEverything() async throws {
        persistence.updateBookmarksLastModified(nil)
        try await dependencies.createUpdatesFetcher(persistence).fetch()
    }
}
