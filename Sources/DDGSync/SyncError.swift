
import Foundation

public enum SyncError: Error {

    #warning ("Remove before merging.")
    case notImplemented

    case noToken

    case failedToCreateAccountKeys
    case accountNotFound
    case accountAlreadyExists

    case noResponseBody
    case unexpectedStatusCode(Int)
    case unableToDecodeResponse(_ message: String)
    case invalidDataInResponse(_ message: String)

    case failedToEncryptValue
    case failedToDecryptValue(_ message: String)

}
