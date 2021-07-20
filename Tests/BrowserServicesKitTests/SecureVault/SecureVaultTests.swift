//
//  SecureVaultTests.swift
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

import XCTest
@testable import BrowserServicesKit

class SecureVaultTests: XCTestCase {

    var mockCryptoProvider = MockCryptoProvider()
    var mockDatabaseProvider = MockDatabaseProvider()
    var mockKeystoreProvider = MockKeystoreProvider()
    var testVault: SecureVault!

    override func setUp() {
        super.setUp()

        let providers = SecureVaultProviders(crypto: mockCryptoProvider,
                                             database: mockDatabaseProvider,
                                             keystore: mockKeystoreProvider)

        testVault = DefaultSecureVault(authExpiry: 1,
                                       providers: providers)

    }

    func testWhenRetrievingAccounts_ThenDatabaseCalled() throws {
        mockDatabaseProvider._accounts = [
            .init(username: "username", domain: "domain")
        ]

        let accounts = try testVault.accounts()

        XCTAssertEqual(1, accounts.count)
        XCTAssertEqual("domain", accounts[0].domain)
        XCTAssertEqual("username", accounts[0].username)
    }

    func testWhenRetrievingAccountsForDomain_ThenDatabaseCalled() throws {

        mockDatabaseProvider._accounts = [
            .init(username: "username", domain: "domain")
        ]

        let accounts = try testVault.accountsFor(domain: "example.com")
        XCTAssertEqual(1, accounts.count)
        XCTAssertEqual("domain", accounts[0].domain)
        XCTAssertEqual("username", accounts[0].username)

        XCTAssertEqual("example.com", mockDatabaseProvider._forDomain)

    }

    func testWhenDeletingCredentialsForAccount_ThenDatabaseCalled() throws {
        let account = SecureVaultModels.WebsiteAccount(id: 1,
                                                       title: "Title",
                                                       username: "test@duck.com",
                                                       domain: "example.com",
                                                       created: Date(),
                                                       lastUpdated: Date())
        mockDatabaseProvider._credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        mockDatabaseProvider._accounts = [account]

        XCTAssertEqual("example.com", mockDatabaseProvider._accounts[0].domain)
        try testVault.deleteWebsiteCredentialsFor(accountId: 1)
        XCTAssert(mockDatabaseProvider._accounts.isEmpty)
    }

    func testWhenAuthorsingWithValidPassword_ThenPasswordValidatedByDecryptingL2Key() throws {

        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encrypted".data(using: .utf8)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)

        _ = try testVault.authWith(password: "password".data(using: .utf8)!)

        XCTAssertEqual(mockCryptoProvider._lastDataToDecrypt, mockKeystoreProvider._encryptedL2Key)
        XCTAssertEqual(mockCryptoProvider._lastKey, mockCryptoProvider._derivedKey)

    }

    func testWhenAuthorsingWithInvalidPassword_ThenPasswordValidatedByDecryptingL2Key() {
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encrypted".data(using: .utf8)

        do {
            _ = try testVault.authWith(password: "password".data(using: .utf8)!)
        } catch {
            if case SecureVaultError.invalidPassword = error {
                // no-op
            } else {
                XCTFail("Unexepected error \(error)")
            }
        }

        XCTAssertEqual(mockCryptoProvider._lastDataToDecrypt, mockKeystoreProvider._encryptedL2Key)
        XCTAssertEqual(mockCryptoProvider._lastKey, mockCryptoProvider._derivedKey)

    }

    func testWhenResetL2Password_ThenL2KeyIsEncryptedAndGeneratedPasswordIsCleared() throws {
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encrypted".data(using: .utf8)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)

        try testVault.resetL2Password(oldPassword: "old".data(using: .utf8), newPassword: "new".data(using: .utf8)!)

        XCTAssertNotNil(mockKeystoreProvider._lastEncryptedL2Key)
        XCTAssertNotNil(mockCryptoProvider._lastDataToEncrypt)
        XCTAssertNotNil(mockCryptoProvider._lastKey)
        XCTAssertTrue(mockKeystoreProvider._generatedPasswordCleared)

    }

    func testWhenStoringWebsiteCredentials_ThenThePasswordIsEncryptedWithL2Key() throws {

        mockKeystoreProvider._generatedPassword = "generated".data(using: .utf8)!
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)!
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)!
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)!

        let passwordToEncrypt = "password".data(using: .utf8)!

        let credentials = SecureVaultModels.WebsiteCredentials(account: .init(username: "test@duck.com", domain: "example.com"),
                                                               password: passwordToEncrypt)

        try testVault.storeWebsiteCredentials(credentials)

        XCTAssertNotNil(mockDatabaseProvider._lastCredentials)
        XCTAssertEqual(mockCryptoProvider._lastDataToEncrypt, passwordToEncrypt)

    }

    func testWhenCredentialsAreRetrievedUsingGeneratedPassword_ThenTheyAreDecrypted() throws {

        let password = "password".data(using: .utf8)!
        let account = SecureVaultModels.WebsiteAccount(username: "test@duck.com", domain: "example.com")
        mockDatabaseProvider._credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)
        mockKeystoreProvider._generatedPassword = "generated".data(using: .utf8)
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)

        let credentials = try testVault.websiteCredentialsFor(accountId: 1)
        XCTAssertNotNil(credentials)
        XCTAssertNotNil(credentials?.password)

        XCTAssertEqual(mockCryptoProvider._lastDataToDecrypt, password)

    }

    func testWhenCredentialsAreRetrievedUsingUserPassword_ThenTheyAreDecrypted() throws {
        let userPassword = "userPassword".data(using: .utf8)!
        let password = "password".data(using: .utf8)!
        let account = SecureVaultModels.WebsiteAccount(username: "test@duck.com", domain: "example.com")
        mockDatabaseProvider._credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)

        let credentials = try testVault.authWith(password: userPassword).websiteCredentialsFor(accountId: 1)

        XCTAssertNotNil(credentials)
        XCTAssertNotNil(credentials?.password)

        XCTAssertEqual(mockCryptoProvider._lastDataToDecrypt, password)
    }

    func testWhenCredentialsAreRetrievedUsingExpiredUserPassword_ThenErrorIsThrown() throws {
        let userPassword = "userPassword".data(using: .utf8)!
        let password = "password".data(using: .utf8)!
        let account = SecureVaultModels.WebsiteAccount(username: "test@duck.com", domain: "example.com")
        mockDatabaseProvider._credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)
        
        _ = try testVault.authWith(password: userPassword)

        sleep(2) // allow vault to expire password

        do {
            _ = try testVault.websiteCredentialsFor(accountId: 1)
        } catch {
            if case SecureVaultError.authRequired = error {
                // no-op
            } else {
                XCTFail("Unexepected error \(error)")
            }
        }
    }

}
    
