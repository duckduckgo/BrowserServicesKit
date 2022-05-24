
import Foundation

public enum SyncError: Error {

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
