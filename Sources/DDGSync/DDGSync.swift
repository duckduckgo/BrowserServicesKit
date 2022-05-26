
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

    public convenience init(persistence: LocalDataPersisting) {
        self.init(persistence: persistence, dependencies: ProductionDependencies(baseUrl: Constants.baseUrl, persistence: persistence))
    }

    public convenience init(persistence: LocalDataPersisting, baseUrl: URL) {
        self.init(persistence: persistence, dependencies: ProductionDependencies(baseUrl: baseUrl, persistence: persistence))
    }

    public func createAccount(device: DeviceDetails) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let account = try await dependencies.account.createAccount(device: device)
        try dependencies.secureStore.persistAccount(account)
    }

    public func login(recoveryKey: Data, device: DeviceDetails) async throws {
        guard try dependencies.secureStore.account() == nil else {
            throw SyncError.accountAlreadyExists
        }

        let result = try await dependencies.account.login(recoveryKey: recoveryKey, device: device)
        try dependencies.secureStore.persistAccount(result.account)
        try await persistence.persistDevices(result.devices)
    }

    public func sender() throws -> AtomicSending {
        return try dependencies.createAtomicSender()
    }

    public func fetchLatest() async throws {
        try await dependencies.createUpdatesFetcher().fetch()
    }

    public func fetchEverything() async throws {
        dependencies.dataLastModified.reset()
        try await dependencies.createUpdatesFetcher().fetch()
    }
}
