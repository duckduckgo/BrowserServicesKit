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
import Combine
@testable import BrowserServicesKit

class SecureVaultTests: XCTestCase {

    var mockCryptoProvider = MockCryptoProvider()
    var mockDatabaseProvider = MockDatabaseProvider()
    var mockKeystoreProvider = MockKeystoreProvider()
    var testVault: SecureVault!

    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()

        let providers = SecureVaultProviders(crypto: mockCryptoProvider,
                                             database: mockDatabaseProvider,
                                             keystore: mockKeystoreProvider)

        testVault = DefaultSecureVault(authExpiry: 1,
                                       providers: providers)

    }

    func testWhenRetrievingAccounts_ThenDatabaseCalled() {

        let ex = expectation(description: "accounts")

        mockDatabaseProvider._accounts = [
            .init(username: "username", domain: "domain")
        ]

        testVault.accounts().sink { _ in
            // This never seems to get called though...
        } receiveValue: {
            ex.fulfill()
            XCTAssertEqual(1, $0.count)
            XCTAssertEqual("domain", $0[0].domain)
            XCTAssertEqual("username", $0[0].username)
        }.store(in: &cancellables)

        waitForExpectations(timeout: 0.3, handler: nil)
    }

    func testWhenRetrievingAccountsForDomain_ThenDatabaseCalled() {

        let ex = expectation(description: "accounts")

        mockDatabaseProvider._accounts = [
            .init(username: "username", domain: "domain")
        ]

        testVault.accountFor(domain: "example.com").sink { _ in
            // This never seems to get called though...
        } receiveValue: {
            ex.fulfill()
            XCTAssertEqual(1, $0.count)
            XCTAssertEqual("domain", $0[0].domain)
            XCTAssertEqual("username", $0[0].username)
        }.store(in: &cancellables)

        waitForExpectations(timeout: 0.3, handler: nil)

        XCTAssertEqual("example.com", mockDatabaseProvider._forDomain)

    }

    func testWhenAuthorsingWithValidPassword_ThenPasswordValidatedByDecryptingL2Key() {
        let ex = expectation(description: "authWith")

        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encrypted".data(using: .utf8)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)

        testVault.authWith(password: "password".data(using: .utf8)!)
            .sink {
                if case .failure(let error) = $0 {
                    XCTFail(error.localizedDescription)
                }
            } receiveValue: { _ in
                ex.fulfill()
            }.store(in: &cancellables)

        waitForExpectations(timeout: 0.3, handler: nil)

        XCTAssertEqual(mockCryptoProvider._lastDataToDecrypt, mockKeystoreProvider._encryptedL2Key)
        XCTAssertEqual(mockCryptoProvider._lastKey, mockCryptoProvider._derivedKey)

    }

    func testWhenAuthorsingWithInvalidPassword_ThenPasswordValidatedByDecryptingL2Key() {
        let ex = expectation(description: "authWith")

        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encrypted".data(using: .utf8)

        testVault.authWith(password: "password".data(using: .utf8)!)
            .sink {
                if case .failure(let error) = $0,
                   case .invalidPassword = error {
                    ex.fulfill()
                }
            } receiveValue: { _ in
            }.store(in: &cancellables)

        waitForExpectations(timeout: 0.3, handler: nil)

        XCTAssertEqual(mockCryptoProvider._lastDataToDecrypt, mockKeystoreProvider._encryptedL2Key)
        XCTAssertEqual(mockCryptoProvider._lastKey, mockCryptoProvider._derivedKey)

    }

    func testWhenResetL2Password_ThenL2KeyIsEncryptedAndGeneratedPasswordIsCleared() {
        let ex = expectation(description: "resetL2Password")

        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encrypted".data(using: .utf8)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)

        testVault.resetL2Password(oldPassword: "old".data(using: .utf8), newPassword: "new".data(using: .utf8)!)
            .sink {
                if case .failure(let error) = $0 {
                    XCTFail(error.localizedDescription)
                }
            } receiveValue: { _ in
                ex.fulfill()
            }.store(in: &cancellables)

        waitForExpectations(timeout: 0.3, handler: nil)

        XCTAssertNotNil(mockKeystoreProvider._lastEncryptedL2Key)
        XCTAssertNotNil(mockCryptoProvider._lastDataToEncrypt)
        XCTAssertNotNil(mockCryptoProvider._lastKey)
        XCTAssertTrue(mockKeystoreProvider._generatedPasswordCleared)

    }

    func testWhenStoringWebsiteCredentials_ThenThePasswordIsEncryptedWithL2Key() {
        let ex = expectation(description: "storeWebsiteCredentials")

        mockKeystoreProvider._generatedPassword = "generated".data(using: .utf8)!
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)!
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)!
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)!

        let passwordToEncrypt = "password".data(using: .utf8)!

        let credentials = SecureVaultModels.WebsiteCredentials(account: .init(username: "test@duck.com", domain: "example.com"),
                                                               password: passwordToEncrypt)

        testVault.storeWebsiteCredentials(credentials).sink {
            if case .failure(let error) = $0 {
                XCTFail(error.localizedDescription)
            }
        } receiveValue: { _ in
            ex.fulfill()
        }.store(in: &cancellables)

        waitForExpectations(timeout: 0.3, handler: nil)

        XCTAssertNotNil(mockDatabaseProvider._lastCredentials)
        XCTAssertEqual(mockCryptoProvider._lastDataToEncrypt, passwordToEncrypt)

    }

    func testWhenCredentialsAreRetrievedUsingGeneratedPassword_ThenTheyAreDecrypted() {
        let ex = expectation(description: "websiteCredentialsFor")

        let password = "password".data(using: .utf8)!
        let account = SecureVaultModels.WebsiteAccount(username: "test@duck.com", domain: "example.com")
        mockDatabaseProvider._credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)
        mockKeystoreProvider._generatedPassword = "generated".data(using: .utf8)
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)

        testVault.websiteCredentialsFor(accountId: 1).sink {
            if case .failure(let error) = $0 {
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            XCTAssertNotNil($0)
            XCTAssertNotNil($0?.password)
            ex.fulfill()
        }.store(in: &cancellables)

        waitForExpectations(timeout: 0.3, handler: nil)

        XCTAssertEqual(mockCryptoProvider._lastDataToDecrypt, password)

    }

    func testWhenCredentialsAreRetrievedUsingUserPassword_ThenTheyAreDecrypted() {
        let ex = expectation(description: "websiteCredentialsFor")

        let userPassword = "userPassword".data(using: .utf8)!
        let password = "password".data(using: .utf8)!
        let account = SecureVaultModels.WebsiteAccount(username: "test@duck.com", domain: "example.com")
        mockDatabaseProvider._credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)

        testVault.authWith(password: userPassword).flatMap {

            $0.websiteCredentialsFor(accountId: 1)

        }.sink {
            if case .failure(let error) = $0 {
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            XCTAssertNotNil($0)
            XCTAssertNotNil($0?.password)
            ex.fulfill()
        }.store(in: &cancellables)

        waitForExpectations(timeout: 0.3, handler: nil)

        XCTAssertEqual(mockCryptoProvider._lastDataToDecrypt, password)

    }

    func testWhenCredentialsAreRetrievedUsingExpiredUserPassword_ThenErrorIsThrown() {
        let userPassword = "userPassword".data(using: .utf8)!
        let password = "password".data(using: .utf8)!
        let account = SecureVaultModels.WebsiteAccount(username: "test@duck.com", domain: "example.com")
        mockDatabaseProvider._credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)
        
        testVault.authWith(password: userPassword).sink {
            if case .failure(let error) = $0 {
                XCTFail(error.localizedDescription)
            }
        } receiveValue: { _ in
            // no-op
        }.store(in: &cancellables)

        sleep(2) // allow vault to expire password

        let ex = expectation(description: "websiteCredentialsFor")

        testVault.websiteCredentialsFor(accountId: 1).sink {
            if case .failure(let error) = $0,
               case .authRequired = error {
                ex.fulfill()
                return
            }

            XCTFail("Didn't get expected error")
        } receiveValue: { _ in
            XCTFail("Unexpected value")
        }.store(in: &cancellables)

        waitForExpectations(timeout: 0.3, handler: nil)
    }

}
    
