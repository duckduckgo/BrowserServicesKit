
import Foundation
import DDGSyncAuth
import Combine

public protocol DDGSyncing {

    var state: SyncState { get }

    func statePublisher() -> AnyPublisher<SyncState, Never>

    /**
     Creates an account.

     Account creation has the following flow:
     * Create a user id and password (UUIDs - future versions will support passing these in)
     * Generate secure keys
     * Call /signup endpoint
     * Store Primary Key, Secret Key, User Id and JWT token
     
     Notes:
     * The primary key in combination with the user id, is the recovery code.  This can be used to (re)connect devices.
     * The JWT token contains the authorisation required to call an endpoint.  If a device is removed from sync the token will be invalidated on the server and subsequent calls will fail.

     */
    func createAccount(device: DeviceDetails) async throws

    /**
    Creates an atomic sender.  Add items to the sender and then call send to send them all in a single package.  Will automatically re-try if there is a network failure.

    Example: A bookmark has been moved to favorites so you want to do the following in a single unit:
        * Delete bookmark
        * Add the favorite
     */
    func sender() throws -> AtomicSending

    /**
    Call this to call the server and get updates.
     */
    func fetch() async throws

    /**
     Updates to bookmarks will be received via this publisher.  You can start receiving even if not authorised, it just won't work.
     */
    func bookmarksPublisher() -> AnyPublisher<SyncEvent<SyncableBookmark>, Never>

}

public protocol AtomicSending {

    func persistBookmark(_ bookmark: SyncableBookmark) -> AtomicSending

    func deleteBookmark(_ bookmark: SyncableBookmark) -> AtomicSending

    func send() async

}

public protocol Syncable {

    var id: UUID { get }
    var version: Int { get }

}

public enum SyncEvent<T: Syncable> {

    case persisted(T)
    case deleted(id: UUID)

}
