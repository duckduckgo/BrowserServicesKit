
import Foundation

public enum SyncError: Error {

    #warning ("Remove before merging.")
    case notImplemented

    case unexpectedState(state: SyncState)

}
