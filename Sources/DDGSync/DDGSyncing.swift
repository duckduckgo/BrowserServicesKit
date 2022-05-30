
import Foundation
import DDGSyncCrypto
import Combine

public protocol DDGSyncing {

    /**
     This client is authenticated if there is an account and a non-null token. If the token is invalidated remotely subsequent requests will set the token to nil and throw an exception.
     */
    var isAuthenticated: Bool { get }

    /**
     Creates an account.

     Account creation has the following flow:
     * Create a device id, user id and password (UUIDs - future versions will support passing these in)
     * Generate secure keys
     * Call /signup endpoint
     * Store Primary Key, Secret Key, User Id and JWT token
     
     Notes:
     * The primary key in combination with the user id, is the recovery code.  This can be used to (re)connect devices.
     * The JWT token contains the authorisation required to call an endpoint.  If a device is removed from sync the token will be invalidated on the server and subsequent calls will fail.

     */
    func createAccount(deviceName: String) async throws

    /**
     Logs in to an existing account.

     The flow is:
     * Extract primary key
     * 

     @param recoveryKey primary key + user id
     */
    func login(recoveryKey: Data, deviceName: String) async throws

    /**
    Creates an atomic sender.  Add items to the sender and then call send to send them all in a single PATCH.  Will automatically re-try if there is a network failure.
     */
    func sender() throws -> AtomicSending

    /**
    Call this to call the server and get latest updated.
     */
    func fetchLatest() async throws

    /**
     Call this to fetch everything again.
    */
    func fetchEverything() async throws

}

public protocol AtomicSending {

    func persistingBookmark(_ bookmark: SavedSiteItem) throws -> AtomicSending
    func persistingBookmarkFolder(_ folder: SavedSiteFolder) throws -> AtomicSending
    func deletingBookmark(_ bookmark: SavedSiteItem) throws -> AtomicSending
    func deletingBookmarkFolder(_ folder: SavedSiteFolder) throws -> AtomicSending

    func send() async throws

}

public enum SyncEvent {

    case bookmarkUpdated(SavedSiteItem)
    case bookmarkFolderUpdated(SavedSiteFolder)
    case bookmarkDeleted(id: String)

}

public struct SavedSiteItem {

    public let id: String

    public let title: String
    public let url: String

    public let isFavorite: Bool
    public let nextFavorite: String?

    public let nextItem: String?
    public let parent: String?

    public init(id: String,
         title: String,
         url: String,
         isFavorite: Bool,
         nextFavorite: String?,
         nextItem: String?,
         parent: String?) {

        self.id = id
        self.title = title
        self.url = url
        self.isFavorite = isFavorite
        self.nextFavorite = nextFavorite
        self.nextItem = nextItem
        self.parent = parent

    }

}

public struct SavedSiteFolder {

    public let id: String

    public let title: String

    public let nextItem: String?
    public let parent: String?

    public init(id: String, title: String, nextItem: String?, parent: String?) {
        self.id = id
        self.title = title
        self.nextItem = nextItem
        self.parent = parent
    }

}
