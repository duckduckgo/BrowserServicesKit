
import Foundation
import Combine

import DDGSyncCrypto

public class DDGSync: DDGSyncing {

    enum Constants {
        public static let baseURL = URL(string: "https://sync.duckduckgo.com")!
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

    public convenience init(persistence: LocalDataPersisting) {
        self.init(persistence: persistence, dependencies: ProductionDependencies(baseURL: Constants.baseURL, persistence: persistence))
    }

    public convenience init(persistence: LocalDataPersisting, baseURL: URL) {
        self.init(persistence: persistence, dependencies: ProductionDependencies(baseURL: baseURL, persistence: persistence))
    }

    public func createAccount(device: DeviceDetails) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let account = try await dependencies.accountCreation.createAccount(device: device)
        try dependencies.secureStore.persistAccount(account)
    }

    public func sender() throws -> AtomicSending {
        return try dependencies.createAtomicSender()
    }

    public func fetchLatest() async throws {
        try await dependencies.createUpdatesFetcher().fetch()
    }

    public func fetchEverything() async throws {
        dependencies.dataLastUpdated.reset()
        try await dependencies.createUpdatesFetcher().fetch()
    }
}
