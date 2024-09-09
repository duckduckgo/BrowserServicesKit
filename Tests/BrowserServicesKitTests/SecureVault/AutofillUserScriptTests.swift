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
import Common
import WebKit

class AutofillUserScriptTests: XCTestCase {

    func testWhenUsernameIsEmpty_ThenAvailableInputTypesUsernameIsFalse() {
        let account = SecureVaultModels.WebsiteAccount(id: "id", username: "", domain: "domain.com", created: Date(), lastUpdated: Date())
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        let credentialsProvider = SecureVaultModels.CredentialsProvider(name: SecureVaultModels.CredentialsProvider.Name.duckduckgo, locked: false)
        let responseFromCredentials = AutofillUserScript.RequestAvailableInputTypesResponse(credentials: [credentials],
                                                                                            identities: [],
                                                                                            cards: [],
                                                                                            email: false,
                                                                                            credentialsProvider: credentialsProvider,
                                                                                            credentialsImport: false)
        XCTAssertEqual(responseFromCredentials.success.credentials.username, false)

        let responseFromAccounts = AutofillUserScript.RequestAvailableInputTypesResponse(accounts: [account],
                                                                                         identities: [],
                                                                                         cards: [],
                                                                                         email: false,
                                                                                         credentialsProvider: credentialsProvider,
                                                                                         credentialsImport: false)
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
                                                                                            credentialsProvider: credentialsProvider,
                                                                                            credentialsImport: false)
        XCTAssertEqual(responseFromCredentials.success.credentials.username, true)

        let responseFromAccounts = AutofillUserScript.RequestAvailableInputTypesResponse(accounts: [account],
                                                                                         identities: [],
                                                                                         cards: [],
                                                                                         email: false,
                                                                                         credentialsProvider: credentialsProvider,
                                                                                         credentialsImport: false)
        XCTAssertEqual(responseFromAccounts.success.credentials.username, true)
    }

    func testWhenPasswordsAreNil_ThenAvailableInputTypesPasswordIsFalse() {
        let credentialsList = createListOfCredentials(withPassword: nil)
        let credentialsProvider = SecureVaultModels.CredentialsProvider(name: SecureVaultModels.CredentialsProvider.Name.duckduckgo, locked: false)
        let responseFromCredentials = AutofillUserScript.RequestAvailableInputTypesResponse(credentials: credentialsList,
                                                                                            identities: [],
                                                                                            cards: [],
                                                                                            email: false,
                                                                                            credentialsProvider: credentialsProvider,
                                                                                            credentialsImport: false)
        XCTAssertEqual(responseFromCredentials.success.credentials.password, false)
    }

    func testWhenAllPasswordsAreEmpty_ThenAvailableInputTypesPasswordIsFalse() {
        let credentialsList = createListOfCredentials(withPassword: "".data(using: .utf8)!)
        let credentialsProvider = SecureVaultModels.CredentialsProvider(name: SecureVaultModels.CredentialsProvider.Name.duckduckgo, locked: false)
        let responseFromCredentials = AutofillUserScript.RequestAvailableInputTypesResponse(credentials: credentialsList,
                                                                                            identities: [],
                                                                                            cards: [],
                                                                                            email: false,
                                                                                            credentialsProvider: credentialsProvider,
                                                                                            credentialsImport: false)
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
                                                                                            credentialsProvider: credentialsProvider,
                                                                                            credentialsImport: false)
        XCTAssertEqual(responseFromCredentials.success.credentials.password, true)
    }

    func testWhenProviderNameIsBitwarden_ThenAvailableInputTypesCredentialsImportIsFalse() {
        let credentialsProvider = SecureVaultModels.CredentialsProvider(name: .bitwarden, locked: false)

        guard let response = getAvailableInputTypesResponse(
            credentialsProvider: credentialsProvider
        ) else {
            XCTFail("No getAvailableInputTypes response")
            return
        }

        XCTAssertFalse(response.success.credentialsImport)
    }

    func testWhenCredentialsForDomainAreNotEmpty_ThenAvailableInputTypesCredentialsImportIsFalse() {
        let credentialsList = createListOfCredentials(withPassword: nil)

        guard let response = getAvailableInputTypesResponse(
            credentialsList: credentialsList
        ) else {
            XCTFail("No getAvailableInputTypes response")
            return
        }

        XCTAssertFalse(response.success.credentialsImport)
    }

    func testWhenTotalCredentialsCountIsTenOrMore_ThenAvailableInputTypesCredentialsImportIsFalse() {
        guard let response = getAvailableInputTypesResponse(
            totalCredentialsCount: 10
        ) else {
            XCTFail("No getAvailableInputTypes response")
            return
        }

        XCTAssertFalse(response.success.credentialsImport)
    }

    func testWhenUserHasImportedLogins_ThenAvailableInputTypesCredentialsImportIsFalse() {
        guard let response = getAvailableInputTypesResponse(
            hasUserImportedLogins: true
        ) else {
            XCTFail("No getAvailableInputTypes response")
            return
        }

        XCTAssertFalse(response.success.credentialsImport)
    }

    func testWhenUserIsNOTNew_ThenAvailableInputTypesCredentialsImportIsFalse() {
        guard let response = getAvailableInputTypesResponse(
            isNewDDGUser: false
        ) else {
            XCTFail("No getAvailableInputTypes response")
            return
        }

        XCTAssertFalse(response.success.credentialsImport)
    }

    func testWhenAutofillIsDisabled_ThenAvailableInputTypesCredentialsImportIsFalse() {
        guard let response = getAvailableInputTypesResponse(
            isAutofillEnabled: false
        ) else {
            XCTFail("No getAvailableInputTypes response")
            return
        }

        XCTAssertFalse(response.success.credentialsImport)
    }

    func testWhenHasNeverPromptWebsitesIsTrue_ThenAvailableInputTypesCredentialsImportIsFalse() {
        guard let response = getAvailableInputTypesResponse(
            hasNeverPromptWebsites: true
        ) else {
            XCTFail("No getAvailableInputTypes response")
            return
        }

        XCTAssertFalse(response.success.credentialsImport)
    }

    func testWhenCredentialsImportPresentationCountIs5_ThenAvailableInputTypesCredentialsImportIsFalse() {
        guard let response = getAvailableInputTypesResponse(
            credentialsImportPresentationCount: 5
        ) else {
            XCTFail("No getAvailableInputTypes response")
            return
        }

        XCTAssertFalse(response.success.credentialsImport)
    }

    func testWhenAllOtherCredentialsImportConditionsAreMet_ThenAvailableInputTypesCredentialsImportIsTrue() {
        guard let response = getAvailableInputTypesResponse() else {
            XCTFail("No getAvailableInputTypes response")
            return
        }

        XCTAssertTrue(response.success.credentialsImport)
    }

    func testStartCredentialsImportFlow_passesDomainFromLastGetAvailableInputsCall() {
        let getAvailableInputsHost = "example.com"
        let hostProvider = MockHostProvider(host: getAvailableInputsHost)
        let userScript = AutofillUserScript(scriptSourceProvider: MockAutofillUserScriptSourceProvider(), hostProvider: hostProvider, loginImportStateProvider: MockAutofillLoginImportStateProvider())
        let vaultDelegate = MockSecureVaultDelegate()
        let passwordImportDelegate = MockAutofillPasswordImportDelegate()

        runGetAvailableInputsAndCredentialsImportFlow(userScript: userScript, vaultDelegate: vaultDelegate, passwordImportDelegate: passwordImportDelegate)

        passwordImportDelegate.autofillUserScriptDidRequestPasswordImportFlowCompletion?()

        XCTAssertEqual(getAvailableInputsHost, vaultDelegate.lastDomain)
    }

    func testStartCredentialsImportFlow_onPasswordImportFlowCompletion_firesDidCloseImportDialogNotification() {
        let userScript = AutofillUserScript(scriptSourceProvider: MockAutofillUserScriptSourceProvider(), loginImportStateProvider: MockAutofillLoginImportStateProvider())
        let passwordImportDelegate = MockAutofillPasswordImportDelegate()
        userScript.passwordImportDelegate = passwordImportDelegate

        userScript.startCredentialsImportFlow(MockWKScriptMessage(name: "", body: "")) { _ in }
        let notificationExpectation = expectation(forNotification: .passwordImportDidCloseImportDialog, object: nil)
        passwordImportDelegate.autofillUserScriptDidRequestPasswordImportFlowCompletion?()

        wait(for: [notificationExpectation], timeout: 5)
    }

    func testStartCredentialsImportFlow_accountsForDomainIsNOTEmpty_callsDidFinishImport() {
        let userScript = AutofillUserScript(scriptSourceProvider: MockAutofillUserScriptSourceProvider(), loginImportStateProvider: MockAutofillLoginImportStateProvider())
        let vaultDelegate = MockSecureVaultDelegate()
        let passwordImportDelegate = MockAutofillPasswordImportDelegate()

        runGetAvailableInputsAndCredentialsImportFlow(userScript: userScript, vaultDelegate: vaultDelegate, passwordImportDelegate: passwordImportDelegate)
        let accounts = createListOfCredentials(withPassword: nil).map(\.account)
        vaultDelegate.didRequestAccountsForDomainCompletionHandler?(accounts, .init(name: .duckduckgo, locked: false))

        XCTAssertTrue(passwordImportDelegate.didCallDidFinishImport)
    }

    func testStartCredentialsImportFlow_credentialsForDomainIsEmpty_doesNOTCallDidFinishImport() {
        let userScript = AutofillUserScript(scriptSourceProvider: MockAutofillUserScriptSourceProvider(), loginImportStateProvider: MockAutofillLoginImportStateProvider())
        let vaultDelegate = MockSecureVaultDelegate()
        let passwordImportDelegate = MockAutofillPasswordImportDelegate()

        runGetAvailableInputsAndCredentialsImportFlow(userScript: userScript, vaultDelegate: vaultDelegate, passwordImportDelegate: passwordImportDelegate)
        passwordImportDelegate.autofillUserScriptDidRequestPasswordImportFlowCompletion?()
        vaultDelegate.didRequestAccountsForDomainCompletionHandler?([], .init(name: .duckduckgo, locked: false))

        XCTAssertFalse(passwordImportDelegate.didCallDidFinishImport)
    }

    // MARK: Private

    // Default vaules here are those that will result in a `true` value for credentialsImport. Override to test `false` case.
    private func getAvailableInputTypesResponse(credentialsList: [SecureVaultModels.WebsiteCredentials] = [],
                                                credentialsProvider: SecureVaultModels.CredentialsProvider = .init(name: .duckduckgo, locked: false),
                                                totalCredentialsCount: Int = 9,
                                                hasUserImportedLogins: Bool = false,
                                                isNewDDGUser: Bool = true,
                                                hasNeverPromptWebsites: Bool = false,
                                                isAutofillEnabled: Bool = true,
                                                credentialsImportPresentationCount: Int = 0,
                                                file: StaticString = #filePath,
                                                line: UInt = #line) -> AutofillUserScript.RequestAvailableInputTypesResponse? {
        let loginImportStateProvider = MockAutofillLoginImportStateProvider()
        loginImportStateProvider.hasImportedLogins = hasUserImportedLogins
        loginImportStateProvider.isNewDDGUser = isNewDDGUser
        loginImportStateProvider.stubHasNeverPromptWebsitesForDomain = hasNeverPromptWebsites
        loginImportStateProvider.isAutofillEnabled = isAutofillEnabled
        loginImportStateProvider.credentialsImportPromptPresentationCount = credentialsImportPresentationCount
        let userScript = AutofillUserScript(scriptSourceProvider: MockAutofillUserScriptSourceProvider(), loginImportStateProvider: loginImportStateProvider)
        let userScriptMessage = MockWKScriptMessage(name: "getAvailableInputTypes", body: "")
        let vaultDelegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = vaultDelegate

        var decodedResponse: AutofillUserScript.RequestAvailableInputTypesResponse?

        userScript.getAvailableInputTypes(userScriptMessage) { response in
            guard let responseData = response?.data(using: .utf8) else {
                XCTFail("Failed to encode JSON data", file: file, line: line)
                return
            }
            guard let decoded = try? JSONDecoder().decode(AutofillUserScript.RequestAvailableInputTypesResponse.self, from: responseData) else {
                XCTFail("Failed to decode JSON from data", file: file, line: line)
                return
            }
            decodedResponse = decoded
        }

        vaultDelegate.didRequestAutoFillInitDataForDomainCompletionHandler?(credentialsList, [], [], credentialsProvider, totalCredentialsCount)

        return decodedResponse
    }

    private func runGetAvailableInputsAndCredentialsImportFlow(userScript: AutofillUserScript, vaultDelegate: MockSecureVaultDelegate, passwordImportDelegate: MockAutofillPasswordImportDelegate) {
        let userScriptMessage = MockWKScriptMessage(name: "getAvailableInputTypes", body: "")
        userScript.vaultDelegate = vaultDelegate
        userScript.passwordImportDelegate = passwordImportDelegate

        userScript.getAvailableInputTypes(userScriptMessage) { _ in }
        userScript.startCredentialsImportFlow(MockWKScriptMessage(name: "", body: "")) { _ in }
        passwordImportDelegate.autofillUserScriptDidRequestPasswordImportFlowCompletion?()
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

class MockAutofillLoginImportStateProvider: AutofillLoginImportStateProvider {
    var credentialsImportPromptPresentationCount: Int = 0

    var isAutofillEnabled: Bool = false

    var stubHasNeverPromptWebsitesForDomain: Bool = false
    func hasNeverPromptWebsitesFor(_ domain: String) -> Bool {
        stubHasNeverPromptWebsitesForDomain
    }
    
    var isNewDDGUser: Bool = false
    var hasImportedLogins: Bool = false
}

class MockAutofillUserScriptSourceProvider: AutofillUserScriptSourceProvider {
    var source: String = ""
}

class MockAutofillPasswordImportDelegate: AutofillPasswordImportDelegate {
    var serializedInputContext: String?
    func autofillUserScriptWillDisplayOverlay(_ serializedInputContext: String) {
        self.serializedInputContext = serializedInputContext
    }

    var autofillUserScriptDidRequestPasswordImportFlowCompletion: (() -> Void)?
    func autofillUserScriptDidRequestPasswordImportFlow(_ completion: @escaping () -> Void) {
        autofillUserScriptDidRequestPasswordImportFlowCompletion = completion
    }

    var didCallDidFinishImport: Bool = false
    func autofillUserScriptDidFinishImportWithImportedCredentialForCurrentDomain() {
        didCallDidFinishImport = true
    }
}
