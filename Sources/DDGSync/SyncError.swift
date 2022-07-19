
import Foundation

public enum SyncError: Error {

    case noToken

    case failedToCreateAccountKeys(_ message: String)
    case accountNotFound
    case accountAlreadyExists

    case noResponseBody
    case unexpectedStatusCode(Int)
    case unableToDecodeResponse(_ message: String)
    case invalidDataInResponse(_ message: String)
    case accountRemoved

    case failedToEncryptValue(_ message: String)
    case failedToDecryptValue(_ message: String)

    case failedToWriteSecureStore(status: OSStatus)
    case failedToReadSecureStore(status: OSStatus)
    case failedToRemoveSecureStore(status: OSStatus)
    
}
