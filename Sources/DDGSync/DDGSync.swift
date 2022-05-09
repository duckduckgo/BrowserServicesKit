
import Foundation
import Combine

import DDGSyncAuth

public class DDGSync: DDGSyncing {

    enum Constants {
        public static let baseURL = URL(string: "https://sync.duckduckgo.com")!
    }

    public private (set) var state: SyncState {
        didSet {
            stateValueSubject.send(state)
        }
    }

    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies

    private let stateValueSubject: CurrentValueSubject<SyncState, Never>

    init(persistence: LocalDataPersisting, dependencies: SyncDependencies) {
        self.state = .noToken
        self.stateValueSubject = CurrentValueSubject(state)
        self.persistence = persistence
        self.dependencies = dependencies
    }

    public convenience init(persistence: LocalDataPersisting) {
        self.init(persistence: persistence, dependencies: ProductionDependencies(baseURL: Constants.baseURL))
    }

    public convenience init(persistence: LocalDataPersisting, baseURL: URL) {
        self.init(persistence: persistence, dependencies: ProductionDependencies(baseURL: baseURL))
    }

    public func statePublisher() -> AnyPublisher<SyncState, Never> {
        return stateValueSubject.share().eraseToAnyPublisher()
    }

    public func createAccount(device: DeviceDetails) async throws {
        guard state != .validToken else { throw SyncError.unexpectedState(state) }
        let account = try await dependencies.accountCreation.createAccount(device: device)
        try dependencies.secureStore.persistAccount(account)
        state = .validToken
    }

    public func sender() throws -> AtomicSending {
        try guardValidToken()
        return try dependencies.createAtomicSender()
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

public protocol LocalDataPersisting {

    func persistBookmark(_ bookmark: SavedSite) async throws

    func persistFavorite(_ favorite: SavedSite) async throws

    func persistBookmarkFolder(_ folder: Folder) async throws

    func persistFavoritesFolder(_ folder: Folder) async throws

    func deleteBookmark(_ bookmark: SavedSite) async throws

    func deleteFavorite(_ favorite: SavedSite) async throws

    func deleteBookmarksFolder(_ folder: Folder) async throws

    func deleteFavoritesFolder(_ folder: Folder) async throws

}
