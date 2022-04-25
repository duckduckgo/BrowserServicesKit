
import Foundation

public enum SyncState {

    /**
     We have not yet attempted to authenticate
     */
    case noToken

    /**
     We have successfully authenticated and are authorised to send and receive updates
     */
    case validToken

    /**
     We previously had a valid token, but now it is not authorized.
     */
    case invalidToken

}
