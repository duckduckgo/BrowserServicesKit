//
//  SecureVault.swift
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
import Combine

/// A vault that supports storing data at various levels.
///
/// * L0 - not encrypted.  Currently no data at this level and we're not likely to use it.
/// * L1 - secret key encrypted.  Usernames, domains, duck addresses.
/// * L2 - user password encrypted and can be accessed without password during a specifed amount of time.  User passwords.
/// * L3 - user password is required at time of request.  Currently no data at this level, but later e.g, credit cards.
///
/// Data always goes in and comes out unencrypted.
public protocol SecureVault {

    func authWith(password: Data) -> AnyPublisher<SecureVault, SecureVaultError>
    func resetL2Password(oldPassword: Data?, newPassword: Data) -> AnyPublisher<Void, SecureVaultError>
    func accounts() -> AnyPublisher<[SecureVaultModels.WebsiteAccount], SecureVaultError>
    func accountFor(domain: String) -> AnyPublisher<[SecureVaultModels.WebsiteAccount], SecureVaultError>
    func websiteCredentialsFor(accountId: String) -> AnyPublisher<SecureVaultModels.WebsiteCredentials?, SecureVaultError>
    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) -> AnyPublisher<Void, SecureVaultError>
    
}

/// Protocols can't be nested, but classes can.  This struct provides a 'namespace' for the default implementations of the providers to keep it clean for other things going on in this library.
internal struct SecureVaultProviders {

    var crypto: SecureVaultCryptoProvider
    var database: SecureVaultDatabaseProvider
    var keystore: SecureVaultKeyStoreProvider

}

class DefaultSecureVault: SecureVault {

    private let queue = DispatchQueue(label: "Secure Vault")

    private let providers: SecureVaultProviders
    private let expiringPassword: ExpiringValue<Data>

    var authExpiry: TimeInterval {
        return expiringPassword.expiresAfter
    }

    internal init(authExpiry: TimeInterval,
                  providers: SecureVaultProviders) {
        self.providers = providers
        self.expiringPassword = ExpiringValue(expiresAfter: authExpiry)
    }

    // MARK: - public interface (protocol candidates)

    /// Sets the password which is retained for the given amount of time. Call this is you receive a `authRequired` error.
    public func authWith(password: Data) -> AnyPublisher<SecureVault, SecureVaultError> {
        return ScheduledFuture(scheduler: self.queue) { promise in
            dispatchPrecondition(condition: .onQueue(self.queue))
            do {
                _ = try self.l2KeyFrom(password: password) // checks the password
                self.expiringPassword.value = password
                promise(.success(self))
            } catch {
                let error = error as? SecureVaultError ?? .authError(cause: error)
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    public func resetL2Password(oldPassword: Data?, newPassword: Data) -> AnyPublisher<Void, SecureVaultError> {
        return ScheduledFuture(scheduler: self.queue) { promise in
            dispatchPrecondition(condition: .onQueue(self.queue))

            // Whatever happens, force a re-auth on future calls
            self.expiringPassword.value = nil

            do {
                // Use the provided old password if provided, or the stored generated password
                let generatedPassword = try self.providers.keystore.generatedPassword()
                guard let oldPassword = oldPassword ?? generatedPassword else {
                    throw SecureVaultError.invalidPassword
                }

                // get decrypted l2key using old password
                let l2Key = try self.l2KeyFrom(password: oldPassword)

                // derive new encryption key
                let newEncryptionKey = try self.providers.crypto.deriveKeyFromPassword(newPassword)

                // encrypt 2 key with new encryption key and nonce
                let encryptedKey = try self.providers.crypto.encrypt(l2Key, withKey: newEncryptionKey)

                // store encrypted L2 key and nonce
                try self.providers.keystore.storeEncryptedL2Key(encryptedKey)

                // Clear the generated password now since we're def using a user provided password
                try self.providers.keystore.clearGeneratedPassword()

                promise(.success(()))
            } catch {

                if let error = error as? SecureVaultError {
                    promise(.failure(error))
                } else {
                    promise(.failure(SecureVaultError.databaseError(cause: error)))
                }

            }

        }.eraseToAnyPublisher()
    }

    public func accounts() -> AnyPublisher<[SecureVaultModels.WebsiteAccount], SecureVaultError> {
        return ScheduledFuture(scheduler: self.queue) { promise in
            dispatchPrecondition(condition: .onQueue(self.queue))
            do {
                let accounts = try self.providers.database.accounts()
                promise(.success(accounts))
            } catch {
                promise(.failure(SecureVaultError.databaseError(cause: error)))
            }
        }
        .eraseToAnyPublisher()
    }

    public func accountFor(domain: String) -> AnyPublisher<[SecureVaultModels.WebsiteAccount], SecureVaultError> {
        return ScheduledFuture(scheduler: self.queue) { promise in
            dispatchPrecondition(condition: .onQueue(self.queue))

            do {
                let results = try self.providers.database.websiteAccountsForDomain(domain)
                promise(.success(results))
            } catch {
                promise(.failure(SecureVaultError.databaseError(cause: error)))
            }
        }
        .eraseToAnyPublisher()
    }

    public func websiteCredentialsFor(accountId: String) -> AnyPublisher<SecureVaultModels.WebsiteCredentials?, SecureVaultError> {
        return ScheduledFuture(scheduler: self.queue) { promise in
            dispatchPrecondition(condition: .onQueue(self.queue))
            do {
                var decryptedCredentials: SecureVaultModels.WebsiteCredentials?
                if let credentials = try self.providers.database.websiteCredentialsForAccountId(accountId) {
                    decryptedCredentials = .init(account: credentials.account,
                                                 password: try self.l2Decrypt(data: credentials.password))
                }
                promise(.success(decryptedCredentials))
            } catch {
                let error = error as? SecureVaultError ?? SecureVaultError.databaseError(cause: error)
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    public func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) -> AnyPublisher<Void, SecureVaultError> {
        return ScheduledFuture(scheduler: self.queue) { promise in
            dispatchPrecondition(condition: .onQueue(self.queue))

            do {
                let encryptedPassword = try self.l2Encrypt(data: credentials.password)
                try self.providers.database.storeWebsiteCredentials(.init(account: credentials.account, password: encryptedPassword))
                promise(.success(()))
            } catch {
                let error = error as? SecureVaultError ?? SecureVaultError.databaseError(cause: error)
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - private

    private func passwordInUse() throws -> Data {
        if let generatedPassword = try providers.keystore.generatedPassword() {
            return generatedPassword
        }

        if let userPassword = expiringPassword.value {
            return userPassword
        }

        throw SecureVaultError.authRequired
    }

    private func l2KeyFrom(password: Data) throws -> Data {
        let decryptionKey = try providers.crypto.deriveKeyFromPassword(password)
        guard let encryptedL2Key = try providers.keystore.encryptedL2Key() else {
            throw SecureVaultError.noL2Key
        }
        return try providers.crypto.decrypt(encryptedL2Key, withKey: decryptionKey)
    }

    private func l2Encrypt(data: Data) throws -> Data {
        let password = try passwordInUse()
        let l2Key = try l2KeyFrom(password: password)
        return try providers.crypto.encrypt(data, withKey: l2Key)
    }

    private func l2Decrypt(data: Data) throws -> Data {
        let password = try passwordInUse()
        let l2Key = try l2KeyFrom(password: password)
        return try providers.crypto.decrypt(data, withKey: l2Key)
    }

}
