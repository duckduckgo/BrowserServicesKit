
import Foundation

public enum SyncError: Error {

    #warning ("Remove before merging.")
    case notImplemented

    case failedToCreateAccountKeys

    case unexpectedState(SyncState)

    case unexpectedStatusCode(Int)
    
}
