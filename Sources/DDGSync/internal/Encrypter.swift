
import Foundation
import DDGSyncCrypto

struct Crypter: Crypting {

    let secureStore: SecureStoring

    func encryptAndBase64Encode(_ value: String) throws -> String {

        var rawBytes = Array(value.utf8)
        var encryptedBytes = [UInt8](repeating: 0, count: rawBytes.count + Int(DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE.rawValue))
        var secretKey = try secureStore.account().secretKey.safeBytes

        guard DDGSYNCCRYPTO_OK == ddgSyncEncrypt(&encryptedBytes, &rawBytes, UInt64(rawBytes.count), &secretKey) else {
            throw SyncError.failedToEncryptValue
        }

        return Data(encryptedBytes).base64EncodedString()
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        guard let data = Data(base64Encoded: value) else {
            throw SyncError.failedToDecryptValue("Unable to decode base64 value")
        }

        var encryptedBytes = data.safeBytes
        var rawBytes = [UInt8](repeating: 0, count: encryptedBytes.count - Int(DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE.rawValue))
        var secretKey = try secureStore.account().secretKey.safeBytes

        guard DDGSYNCCRYPTO_OK == ddgSyncDecrypt(&rawBytes, &encryptedBytes, UInt64(encryptedBytes.count), &secretKey) else {
            throw SyncError.failedToDecryptValue("decryption failed")
        }

        guard let result = String(data: Data(rawBytes), encoding: .utf8) else {
            throw SyncError.failedToDecryptValue("bytes could not be converted to string")
        }

        return result
    }

}

extension Data {

    var safeBytes: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        copyBytes(to: &bytes, from: 0 ..< count)
        return bytes
    }

}
