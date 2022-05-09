
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

}

public protocol AtomicSending {

    mutating func persistBookmark(_ bookmark: SavedSite)
    mutating func persistBookmarkFolder(_ folder: Folder)
    mutating func deleteBookmark(_ bookmark: SavedSite)
    mutating func deleteBookmarkFolder(_ folder: Folder)

    mutating func persistFavorite(_ favorite: SavedSite)
    mutating func persistFavoriteFolder(_ favorite: Folder)
    mutating func deleteFavorite(_ favorite: SavedSite)
    mutating func deleteFavoriteFolder(_ favorite: Folder)

    func send() async throws

}

public enum SyncEvent {

    case bookmarkUpdated(SavedSite)
    case bookmarkFolderUpdated(Folder)
    case bookmarkDeleted(id: String)
    case favoriteUpdated(SavedSite)
    case favoriteFolderUpdated(Folder)
    case favoriteDeleted(id: String)

}


public struct SavedSite {

    public let id: String

    public let title: String
    public let url: String
    public let position: Double

    public let parent: String?

    public init(id: String, title: String, url: String, position: Double, parent: String?) {
        self.id = id
        self.title = title
        self.url = url
        self.position = position
        self.parent = parent
    }

}

public struct Folder {

    public let id: String

    public let title: String
    public let position: Double

    public let parent: String?

    public init(id: String, title: String,position: Double, parent: String?) {
        self.id = id
        self.title = title
        self.position = position
        self.parent = parent
    }

}
