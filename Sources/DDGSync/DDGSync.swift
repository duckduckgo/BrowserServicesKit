
import Foundation
import Combine

public class DDGSync: DDGSyncing {

    public private (set) var state: SyncState

    public init() {
        state = .noToken
    }

    public func statePublisher() -> AnyPublisher<SyncState, Never> {
        return CurrentValueSubject(state).eraseToAnyPublisher()
    }

    public func createAccount() async throws {
        try guardValidToken()
        throw SyncError.notImplemented
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
        guard state != .validToken else {
            throw SyncError.unexpectedState(state: state)
        }
    }
}
