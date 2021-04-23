//
//  SecureVaultCryptoProvider.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import CommonCrypto
import CryptoKit

protocol SecureVaultCryptoProvider {

    func generateSecretKey() throws -> Data

    func generatePassword() throws -> Data

    func deriveKeyFromPassword(_ password: Data) throws -> Data

    func encrypt(_ data: Data, withKey key: Data) throws -> Data

    func decrypt(_ data: Data, withKey key: Data) throws -> Data

}

final class DefaultCryptoProvider: SecureVaultCryptoProvider {

    static let passwordSalt = "33EF1524-0DEA-4201-9B51-19230121EADB".data(using: .utf8)!
    static let keySizeInBytes = 256 / 8

    func generateSecretKey() throws -> Data {
        return SymmetricKey(size: .bits256).dataRepresentation
    }

    func generatePassword() throws -> Data {
        var data = Data(count: Self.keySizeInBytes)
        let result = data.withUnsafeMutableBytes {
            return SecRandomCopyBytes(kSecRandomDefault, Self.keySizeInBytes, $0.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw SecureVaultError.secError(status: result)
        }
        return data
    }

    func deriveKeyFromPassword(_ password: Data) throws -> Data {
        let salt = Self.passwordSalt
        var key = Data(repeating: 0, count: Self.keySizeInBytes)
        let keyLength = key.count
        let status: OSStatus = key.withUnsafeMutableBytes { derivedKeyBytes in
            let derivedKeyRawBytes = derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress
            return salt.withUnsafeBytes { saltBytes in
                let rawSaltBytes = saltBytes.bindMemory(to: UInt8.self).baseAddress
                return password.withUnsafeBytes { passwordBytes in
                    let rawPasswordBytes = passwordBytes.bindMemory(to: Int8.self).baseAddress
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        rawPasswordBytes,
                        password.count,
                        rawSaltBytes,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(1024),
                        derivedKeyRawBytes,
                        keyLength)
                }
            }
        }

        guard status == kCCSuccess else {
            throw SecureVaultError.secError(status: status)
        }

        return key
    }

    func encrypt(_ data: Data, withKey key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedData = try AES.GCM.seal(data, using: symmetricKey)
        guard let data = sealedData.combined else {
            throw SecureVaultError.generalCryptoError
        }
        return data
    }

    func decrypt(_ data: Data, withKey key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        do {
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            if case CryptoKitError.authenticationFailure = error {
                throw SecureVaultError.invalidPassword
            } else {
                throw error
            }
        }
    }

}

fileprivate extension ContiguousBytes {

    var dataRepresentation: Data {
        return self.withUnsafeBytes { bytes in
            return Data(bytes)
        }
    }

}
