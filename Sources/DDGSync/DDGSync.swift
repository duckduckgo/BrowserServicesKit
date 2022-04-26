
import Foundation
import Combine

import DDGSyncAuth

public class DDGSync: DDGSyncing {

    enum Constants {
        public static let baseURL = URL(string: "https://sync.duckduckgo.com")!
    }

    public private (set) var state: SyncState

    let dependencies: SyncDependencies

    init(dependencies: SyncDependencies) {
        self.state = .noToken
        self.dependencies = dependencies
    }

    public convenience init() {
        self.init(dependencies: ProductionDependencies(baseURL: Constants.baseURL))
    }

    public convenience init(baseURL: URL) {
        self.init(dependencies: ProductionDependencies(baseURL: baseURL))
    }

    public func statePublisher() -> AnyPublisher<SyncState, Never> {
        return CurrentValueSubject(state).eraseToAnyPublisher()
    }

    public func createAccount(device: DeviceDetails) async throws {
        guard state != .validToken else { throw SyncError.unexpectedState(state) }
        let account = try await dependencies.accountCreation.createAccount(device: device)
        try dependencies.secureStore.persistAccount(account)
        state = .validToken
    }

    public func bookmarksPublisher() -> AnyPublisher<SyncEvent<SyncableBookmark>, Never> {
        return PassthroughSubject().eraseToAnyPublisher()
    }

    public func sender() throws -> AtomicSender {
        try guardValidToken()
        throw SyncError.notImplemented
    }

    public func fetch() async throws {
        try guardValidToken()
    }

    private func guardValidToken() throws {
        guard state == .validToken else {
            throw SyncError.unexpectedState(state)
        }
    }
}
