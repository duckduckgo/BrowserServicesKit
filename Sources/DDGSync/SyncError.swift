
import Foundation

public enum SyncError: Error {

    #warning ("Remove before merging.")
    case notImplemented

    case failedToCreateAccountKeys
    case noResponseBody
    case unexpectedState(SyncState)
    case unexpectedStatusCode(Int)
    case unableToDecodeResponse(_ message: String)
    case invalidDataInResponse(_ message: String)
    case accountNotFound
    case failedToEncryptValue
    case failedToDecryptValue(_ message: String)

}
