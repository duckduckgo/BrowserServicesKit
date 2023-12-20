//
//  SecureVaultFactory.swift
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

public protocol SecureVaultErrorReporting: AnyObject {
    func secureVaultInitFailed(_ error: SecureStorageError)
}

/// Can make a SecureVault instance with given specification.  May return previously created instance if specification is unchanged.
public class SecureVaultFactory<Vault: SecureVault> {

    public typealias CryptoProviderInitialization = () -> SecureStorageCryptoProvider
    public typealias KeyStoreProviderInitialization = () -> SecureStorageKeyStoreProvider
    public typealias DatabaseProviderInitialization = (_ key: Data) throws -> Vault.DatabaseProvider

    private var lock = NSLock()
    private var vault: Vault?

    public let makeCryptoProvider: CryptoProviderInitialization
    public let makeKeyStoreProvider: KeyStoreProviderInitialization
    public let makeDatabaseProvider: DatabaseProviderInitialization

    /// You should really use the `default` accessor.
    public init(makeCryptoProvider: @escaping CryptoProviderInitialization,
                makeKeyStoreProvider: @escaping KeyStoreProviderInitialization,
                makeDatabaseProvider: @escaping DatabaseProviderInitialization) {
        self.makeCryptoProvider = makeCryptoProvider
        self.makeKeyStoreProvider = makeKeyStoreProvider
        self.makeDatabaseProvider = makeDatabaseProvider
    }

    /// Returns an initialised SecureVault instance that respects the user password.
    ///
    /// The first time this is ever called the following is performed:
    /// * Generates a secret key for L1 encryption and stores in Keychain
    /// * Generates a secret key for L2 encryption
    /// * Generates a user password to encrypt the L2 key with
    /// * Stores encrypted L2 key in Keychain
    public func makeVault(errorReporter: SecureVaultErrorReporting?) throws -> Vault {
        if let vault = self.vault {
            return vault
        } else {
            lock.lock()
            defer {
                lock.unlock()
            }

            do {
                let providers = try makeSecureStorageProviders()
                let vault = Vault(providers: providers)

                self.vault = vault

                return vault

            } catch let error as SecureStorageError {
                errorReporter?.secureVaultInitFailed(error)
                throw error
            } catch {
                errorReporter?.secureVaultInitFailed(SecureStorageError.initFailed(cause: error))
                throw SecureStorageError.initFailed(cause: error)
            }
        }
    }

    public func makeSecureStorageProviders() throws -> SecureStorageProviders<Vault.DatabaseProvider> {
        let (cryptoProvider, keystoreProvider): (SecureStorageCryptoProvider, SecureStorageKeyStoreProvider)
        do {
            (cryptoProvider, keystoreProvider) = try createAndInitializeEncryptionProviders()
        } catch {
            throw SecureStorageError.initFailed(cause: error)
        }
        guard let existingL1Key = try keystoreProvider.l1Key() else { throw SecureStorageError.noL1Key }

        do {
            let databaseProvider = try self.makeDatabaseProvider(existingL1Key)
            return SecureStorageProviders(crypto: cryptoProvider, database: databaseProvider, keystore: keystoreProvider)
        } catch {
            throw SecureStorageError.failedToOpenDatabase(cause: error)
        }
    }

    public func createAndInitializeEncryptionProviders() throws -> (SecureStorageCryptoProvider, SecureStorageKeyStoreProvider) {
        let cryptoProvider = makeCryptoProvider()
        let keystoreProvider = makeKeyStoreProvider()

        if try keystoreProvider.l1Key() != nil {
            return (cryptoProvider, keystoreProvider)
        } else {
            let l1Key = try cryptoProvider.generateSecretKey()
            let l2Key = try cryptoProvider.generateSecretKey()
            let password = try cryptoProvider.generatePassword()
            let passwordKey = try cryptoProvider.deriveKeyFromPassword(password)
            let encryptedL2Key = try cryptoProvider.encrypt(l2Key, withKey: passwordKey)

            try keystoreProvider.storeEncryptedL2Key(encryptedL2Key)
            try keystoreProvider.storeGeneratedPassword(password)
            try keystoreProvider.storeL1Key(l1Key)

            return (cryptoProvider, keystoreProvider)
        }
    }

}
