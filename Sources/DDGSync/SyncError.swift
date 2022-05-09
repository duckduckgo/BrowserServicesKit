
import Foundation

public enum SyncError: Error {

    #warning ("Remove before merging.")
    case notImplemented

    case failedToCreateAccountKeys
    case noResponseBody
    case unexpectedState(SyncState)
    case unexpectedStatusCode(Int)
    case unableToDecodeResponse(message: String)
    case invalidDataInResponse(message: String)
    case accountNotFound

}
