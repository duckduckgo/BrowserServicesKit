//
//  AutofillUserScriptTests.swift
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
import XCTest
import CryptoKit
@testable import BrowserServicesKit

class AutofillUserScriptTests: XCTestCase {

    func testWhenUsernameIsEmpty_ThenAvailableInputTypesUsernameIsFalse() {
        let account = SecureVaultModels.WebsiteAccount(id: "id", username: "", domain: "domain.com", created: Date(), lastUpdated: Date())
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        let credentialsProvider = SecureVaultModels.CredentialsProvider(name: SecureVaultModels.CredentialsProvider.Name.duckduckgo, locked: false)
        let responseFromCredentials = AutofillUserScript.RequestAvailableInputTypesResponse(credentials: [credentials],
                                                                                            identities: [],
                                                                                            cards: [],
                                                                                            email: false,
                                                                                            credentialsProvider: credentialsProvider)
        XCTAssertEqual(responseFromCredentials.success.credentials.username, false)

        let responseFromAccounts = AutofillUserScript.RequestAvailableInputTypesResponse(accounts: [account],
                                                                                         identities: [],
                                                                                         cards: [],
                                                                                         email: false,
                                                                                         credentialsProvider: credentialsProvider)
        XCTAssertEqual(responseFromAccounts.success.credentials.username, false)
    }

    func testWhenUsernameIsNotEmpty_ThenAvailableInputTypesUsernameIsTrue() {
        let account = SecureVaultModels.WebsiteAccount(id: "id", username: "username", domain: "domain.com", created: Date(), lastUpdated: Date())
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        let credentialsProvider = SecureVaultModels.CredentialsProvider(name: SecureVaultModels.CredentialsProvider.Name.duckduckgo, locked: false)
        let responseFromCredentials = AutofillUserScript.RequestAvailableInputTypesResponse(credentials: [credentials],
                                                                             identities: [],
                                                                             cards: [],
                                                                             email: false,
                                                                             credentialsProvider: credentialsProvider)
        XCTAssertEqual(responseFromCredentials.success.credentials.username, true)

        let responseFromAccounts = AutofillUserScript.RequestAvailableInputTypesResponse(accounts: [account],
                                                                                         identities: [],
                                                                                         cards: [],
                                                                                         email: false,
                                                                                         credentialsProvider: credentialsProvider)
        XCTAssertEqual(responseFromAccounts.success.credentials.username, true)
    }

    func testWhenPasswordsAreNil_ThenAvailableInputTypesPasswordIsFalse() {
        let credentialsList = createListOfCredentials(withPassword: nil)
        let credentialsProvider = SecureVaultModels.CredentialsProvider(name: SecureVaultModels.CredentialsProvider.Name.duckduckgo, locked: false)
        let responseFromCredentials = AutofillUserScript.RequestAvailableInputTypesResponse(credentials: credentialsList,
                                                                                            identities: [],
                                                                                            cards: [],
                                                                                            email: false,
                                                                                            credentialsProvider: credentialsProvider)
        XCTAssertEqual(responseFromCredentials.success.credentials.password, false)
    }

    func testWhenAllPasswordsAreEmpty_ThenAvailableInputTypesPasswordIsFalse() {
        let credentialsList = createListOfCredentials(withPassword: "".data(using: .utf8)!)
        let credentialsProvider = SecureVaultModels.CredentialsProvider(name: SecureVaultModels.CredentialsProvider.Name.duckduckgo, locked: false)
        let responseFromCredentials = AutofillUserScript.RequestAvailableInputTypesResponse(credentials: credentialsList,
                                                                                            identities: [],
                                                                                            cards: [],
                                                                                            email: false,
                                                                                            credentialsProvider: credentialsProvider)
        XCTAssertEqual(responseFromCredentials.success.credentials.password, false)
    }

    func testWhenAtLeastOnePasswordIsNonNilOrEmpty_ThenAvailableInputTypesPasswordIsTrue() {
        var credentialsList = createListOfCredentials(withPassword: nil)
        let account = credentialsList.first?.account
        let credentialsWithPassword = SecureVaultModels.WebsiteCredentials(account: account!, password: "password".data(using: .utf8)!)
        credentialsList.append(credentialsWithPassword)
        let credentialsProvider = SecureVaultModels.CredentialsProvider(name: SecureVaultModels.CredentialsProvider.Name.duckduckgo, locked: false)
        let responseFromCredentials = AutofillUserScript.RequestAvailableInputTypesResponse(credentials: credentialsList,
                                                                                            identities: [],
                                                                                            cards: [],
                                                                                            email: false,
                                                                                            credentialsProvider: credentialsProvider)
        XCTAssertEqual(responseFromCredentials.success.credentials.password, true)
    }

    private func createListOfCredentials(withPassword password: Data?) -> [SecureVaultModels.WebsiteCredentials] {
        var credentialsList = [SecureVaultModels.WebsiteCredentials]()
        for i in 0...10 {
            let account = SecureVaultModels.WebsiteAccount(id: "id\(i)", username: "username\(i)", domain: "domain.com", created: Date(), lastUpdated: Date())
            let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password)
            credentialsList.append(credentials)
        }
        return credentialsList
    }
}
