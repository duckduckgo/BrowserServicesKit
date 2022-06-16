
import Foundation
import DDGSyncCrypto

struct Crypter: Crypting {

    let secureStore: SecureStoring

    func encryptAndBase64Encode(_ value: String) throws -> String {
        guard let account = try secureStore.account() else {
            throw SyncError.accountNotFound
        }

        var rawBytes = Array(value.utf8)
        var encryptedBytes = [UInt8](repeating: 0, count: rawBytes.count + Int(DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE.rawValue))
        var secretKey = account.secretKey.safeBytes

        let result = ddgSyncEncrypt(&encryptedBytes, &rawBytes, UInt64(rawBytes.count), &secretKey)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToEncryptValue("ddgSyncEncrypt failed: \(result)")
        }

        return Data(encryptedBytes).base64EncodedString()
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        guard let account = try secureStore.account() else {
            throw SyncError.accountNotFound
        }

        guard let data = Data(base64Encoded: value) else {
            throw SyncError.failedToDecryptValue("Unable to decode base64 value")
        }

        var encryptedBytes = data.safeBytes
        var rawBytes = [UInt8](repeating: 0, count: encryptedBytes.count - Int(DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE.rawValue))
        var secretKey = account.secretKey.safeBytes

        let result = ddgSyncDecrypt(&rawBytes, &encryptedBytes, UInt64(encryptedBytes.count), &secretKey)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToDecryptValue("ddgSyncDecrypt failed: \(result)")
        }

        guard let decryptedValue = String(data: Data(rawBytes), encoding: .utf8) else {
            throw SyncError.failedToDecryptValue("bytes could not be converted to string")
        }

        return decryptedValue
    }

    func createAccountCreationKeys(userId: String, password: String) throws -> (primaryKey: Data, secretKey: Data, protectedSecretKey: Data, passwordHash: Data) {

        var primaryKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))
        var secretKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
        var protectedSecretKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PROTECTED_SECRET_KEY_SIZE.rawValue))
        var passwordHash = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_HASH_SIZE.rawValue))

        let result = ddgSyncGenerateAccountKeys(&primaryKey, &secretKey, &protectedSecretKey, &passwordHash, userId, password)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToCreateAccountKeys("ddgSyncGenerateAccountKeys() failed: \(result)")
        }

        return (
            primaryKey: Data(primaryKey),
            secretKey: Data(secretKey),
            protectedSecretKey: Data(protectedSecretKey),
            passwordHash: Data(passwordHash)
        )
    }

    func extractLoginInfo(recoveryKey: Data) throws -> (userId: String, primaryKey: Data, passwordHash: Data, stretchedPrimaryKey: Data) {
        let primaryKeySize = Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue)
        guard recoveryKey.count > primaryKeySize else { throw SyncError.failedToCreateAccountKeys("Recovery key is not valid") }
        
        var primaryKeyBytes = [UInt8](repeating: 0, count: primaryKeySize)
        var userIdBytes = [UInt8](repeating: 0, count: recoveryKey.count - primaryKeySize)
        var passwordHashBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_HASH_SIZE.rawValue))
        var strechedPrimaryKeyBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_STRETCHED_PRIMARY_KEY_SIZE.rawValue))

        recoveryKey.copyBytes(to: &primaryKeyBytes, from: 0 ..< primaryKeySize)
        recoveryKey.copyBytes(to: &userIdBytes, from: primaryKeySize ..< recoveryKey.count)
             
        guard let userId = String(data: Data(userIdBytes), encoding: .utf8) else {
            throw SyncError.failedToCreateAccountKeys("failed to get userId from recovery key")
        }
        
        let result = ddgSyncPrepareForLogin(&passwordHashBytes, &strechedPrimaryKeyBytes, &primaryKeyBytes)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToCreateAccountKeys("ddgSyncPrepareForLogin failed: \(result)")
        }
        
        return (
            userId: userId,
            primaryKey: Data(primaryKeyBytes),
            passwordHash: Data(passwordHashBytes),
            stretchedPrimaryKey: Data(strechedPrimaryKeyBytes)
        )

    }

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data {
        var secretKeyBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
        var protectedSecretKeyBytes = protectedSecretKey.safeBytes
        assert(protectedSecretKey.count == DDGSYNCCRYPTO_PROTECTED_SECRET_KEY_SIZE.rawValue)
        
        var stretchedPrimaryKeyBytes = stretchedPrimaryKey.safeBytes
        assert(stretchedPrimaryKeyBytes.count == DDGSYNCCRYPTO_STRETCHED_PRIMARY_KEY_SIZE.rawValue)

        let result = ddgSyncDecrypt(&secretKeyBytes, &protectedSecretKeyBytes, UInt64(protectedSecretKeyBytes.count), &stretchedPrimaryKeyBytes)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToCreateAccountKeys("ddgSyncDecrypt failed: \(result)")
        }
        
        return Data(secretKeyBytes)
    }

}

extension Data {

    var safeBytes: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        copyBytes(to: &bytes, from: 0 ..< count)
        return bytes
    }

}
