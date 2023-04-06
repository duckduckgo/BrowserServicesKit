//
//  SecureVaultManagerTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import UserScript
@testable import BrowserServicesKit

class SecureVaultManagerTests: XCTestCase {
    
    private var mockCryptoProvider = NoOpCryptoProvider()
    private var mockDatabaseProvider = MockDatabaseProvider()
    private var mockKeystoreProvider = MockKeystoreProvider()
    
    private let mockAutofillUserScript: AutofillUserScript = {
        let embeddedConfig =
        """
        {
            "features": {
                "autofill": {
                    "status": "enabled",
                    "exceptions": []
                }
            },
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!
        let privacyConfig = AutofillTestHelper.preparePrivacyConfig(embeddedConfig: embeddedConfig)
        let properties = ContentScopeProperties(gpcEnabled: false, sessionKey: "1234", featureToggles: ContentScopeFeatureToggles.allTogglesOn)
        let sourceProvider = DefaultAutofillSourceProvider(privacyConfigurationManager: privacyConfig,
                                                           properties: properties)
        return AutofillUserScript(scriptSourceProvider: sourceProvider, encrypter: MockEncrypter(), hostProvider: SecurityOriginHostProvider())
    }()
    
    private var testVault: SecureVault!
    private var secureVaultManagerDelegate: MockSecureVaultManagerDelegate!
    private var manager: SecureVaultManager!

    override func setUp() {
        super.setUp()

        mockKeystoreProvider._generatedPassword = "generated".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)

        let providers = SecureVaultProviders(crypto: mockCryptoProvider, database: mockDatabaseProvider, keystore: mockKeystoreProvider)
        
        self.testVault = DefaultSecureVault(authExpiry: 30, providers: providers)
        self.secureVaultManagerDelegate = MockSecureVaultManagerDelegate()
        self.manager = SecureVaultManager(vault: self.testVault)
        self.manager.delegate = secureVaultManagerDelegate
    }
    
    func testWhenGettingExistingEntries_AndNoAutofillDataWasProvided_AndNoEntriesExist_ThenReturnValueIsNil() throws {
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: nil, creditCard: nil)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData, automaticallySavedCredentials: false)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNil(entries.creditCard)
    }
    
    func testWhenGettingExistingEntries_AndAutofillCreditCardWasProvided_AndNoMatchingCreditCardExists_ThenReturnValueIncludesCard() throws {
        let card = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 2022)

        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: nil, creditCard: card)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData, automaticallySavedCredentials: false)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNotNil(entries.creditCard)
        XCTAssertTrue(entries.creditCard!.hasAutofillEquality(comparedTo: card))
    }
    
    func testWhenGettingExistingEntries_AndAutofillCreditCardWasProvided_AndMatchingCreditCardExists_ThenReturnValueIsNil() throws {
        let card = paymentMethod(id: 1, cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 2022)
        try self.testVault.storeCreditCard(card)

        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: nil, creditCard: card)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData, automaticallySavedCredentials: false)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNil(entries.creditCard)
    }
    
    func testWhenGettingExistingEntries_AndAutofillIdentityWasProvided_AndNoMatchingIdentityExists_ThenReturnValueIncludesIdentity() throws {
        let identity = identity(name: ("First", "Middle", "Last"), addressStreet: "Address Street")
        
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: identity, credentials: nil, creditCard: nil)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData, automaticallySavedCredentials: false)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.creditCard)
        XCTAssertNotNil(entries.identity)
        XCTAssertTrue(entries.identity!.hasAutofillEquality(comparedTo: identity))
    }
    
    func testWhenGettingExistingEntries_AndAutofillIdentityWasProvided_AndMatchingIdentityExists_ThenReturnValueIsNil() throws {
        let identity = identity(id: 1, name: ("First", "Middle", "Last"), addressStreet: "Address Street")
        try self.testVault.storeIdentity(identity)

        let autofillData = AutofillUserScript.DetectedAutofillData(identity: identity, credentials: nil, creditCard: nil)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData, automaticallySavedCredentials: false)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNil(entries.creditCard)
    }
    
    // MARK: - AutofillSecureVaultDelegate Tests
    
    func testWhenRequestingToStoreCredentials_AndCredentialsDoNotExist_ThenTheDelegateIsPromptedToStoreAutofillData() {
        let incomingCredentials = AutofillUserScript.IncomingCredentials(username: "username", password: "password", autogenerated: false)
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil)
        
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "domain.com", data: autofillData)
        XCTAssertNotNil(secureVaultManagerDelegate.promptedAutofillData)
        XCTAssertEqual(incomingCredentials, autofillData.credentials)
    }
    
    func testWhenRequestingToStoreCredentials_AndCredentialsAreGenerated_AndNoCredentialsAlreadyExist_ThenTheDelegateIsPromptedToStoreAutofillData() throws {
        let incomingCredentials = AutofillUserScript.IncomingCredentials(username: nil, password: "password", autogenerated: true)
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil)
        
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "domain.com", data: autofillData)
        XCTAssertNotNil(secureVaultManagerDelegate.promptedAutofillData)
        
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.account.username, "")
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.account.domain, "domain.com")
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.password, "password".data(using: .utf8)!)
    }
    
    func testWhenRequestingToStoreCredentials_AndCredentialsAreAutoGenerated_AndCredentialsAlreadyExist_ThenPromptedAutofillDataIsEmpty() throws {
        let domain = "domain.com"
        let account = SecureVaultModels.WebsiteAccount(id: "1", title: nil, username: "", domain: domain, created: Date(), lastUpdated: Date())
        self.mockDatabaseProvider._accounts = [account]
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        try self.testVault.storeWebsiteCredentials(credentials)

        let incomingCredentials = AutofillUserScript.IncomingCredentials(username: "", password: "password", autogenerated: true)
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil)
        
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: domain, data: autofillData)
        XCTAssertNotNil(secureVaultManagerDelegate.promptedAutofillData)
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData?.credentials)
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData?.creditCard)
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData?.identity)
    }
    
    func testWhenRequestingToStoreCredentials_AndCredentialsAreNotAutoGenerated_AndCredentialsAlreadyExist_ThenPromptedAutofillDataIsEmpty() throws {
        let domain = "domain.com"
        let account = SecureVaultModels.WebsiteAccount(id: "1", title: nil, username: "username", domain: domain, created: Date(), lastUpdated: Date())
        self.mockDatabaseProvider._accounts = [account]
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        try self.testVault.storeWebsiteCredentials(credentials)

        let incomingCredentials = AutofillUserScript.IncomingCredentials(username: "username", password: "password", autogenerated: false)
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil)
        
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: domain, data: autofillData)
        XCTAssertNotNil(secureVaultManagerDelegate.promptedAutofillData)
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData?.credentials)
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData?.creditCard)
        XCTAssertNil(secureVaultManagerDelegate.promptedAutofillData?.identity)
    }

    func testWhenRequestingCredentialsWithEmptyUsername_ThenNonActionIsReturned() throws {
        let triggerType = AutofillUserScript.GetTriggerType.userInitiated

        // account
        let domain = "domain.com"
        let username = "" // <- this is a valid scenario
        let account = SecureVaultModels.WebsiteAccount(id: "1", title: nil, username: username, domain: domain, created: Date(), lastUpdated: Date())
        self.mockDatabaseProvider._accounts = [account]

        // credentials for the account
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        try self.testVault.storeWebsiteCredentials(credentials)

        let subType = AutofillUserScript.GetAutofillDataSubType.username
        let expect = expectation(description: #function)
        manager.autofillUserScript(mockAutofillUserScript, didRequestCredentialsForDomain: domain, subType: subType, trigger: triggerType) { credentials, provider, action in
            XCTAssertEqual(action, .none)
            XCTAssertNil(credentials)
            expect.fulfill()
        }
        waitForExpectations(timeout: 0.1)
    }

    func testWhenRequestingCredentialsWithNonEmptyUsername_ThenFillActionIsReturned() throws {
        class SecureVaultDelegate: MockSecureVaultManagerDelegate {
            override func secureVaultManager(_ manager: SecureVaultManager,
                                             promptUserToAutofillCredentialsForDomain domain: String,
                                             withAccounts accounts: [SecureVaultModels.WebsiteAccount],
                                             withTrigger trigger: AutofillUserScript.GetTriggerType,
                                             completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void) {
                XCTAssertEqual(accounts.count, 1, "The empty username should have been filtered so that it's not shown as an option")
                completionHandler(accounts[0])
            }
        }

        self.secureVaultManagerDelegate = SecureVaultDelegate()
        self.manager.delegate = self.secureVaultManagerDelegate
        
        let triggerType = AutofillUserScript.GetTriggerType.userInitiated

        // account 1 (empty username)
        let domain = "domain.com"
        let username = ""
        let account = SecureVaultModels.WebsiteAccount(id: "1", title: nil, username: username, domain: domain, created: Date(), lastUpdated: Date())

        // account 2
        let username2 = "dax2"
        let account2 = SecureVaultModels.WebsiteAccount(id: "2", title: nil, username: username2, domain: domain, created: Date(), lastUpdated: Date())
        self.mockDatabaseProvider._accounts = [account, account2]

        // credential for the account
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        let credentials2 = SecureVaultModels.WebsiteCredentials(account: account2, password: "password".data(using: .utf8)!)
        try self.testVault.storeWebsiteCredentials(credentials)
        try self.testVault.storeWebsiteCredentials(credentials2)

        let subType = AutofillUserScript.GetAutofillDataSubType.username
        let expect = expectation(description: #function)
        manager.autofillUserScript(mockAutofillUserScript, didRequestCredentialsForDomain: domain, subType: subType, trigger: triggerType) { credentials, provider, action in
            XCTAssertEqual(action, .fill)
            XCTAssertEqual(credentials!.password, "password".data(using: .utf8)!)
            XCTAssertEqual(credentials!.account.username, "dax2")
            expect.fulfill()
        }
        waitForExpectations(timeout: 0.1)
    }

    func testWhenRequestingCredentialsWithPasswordSubtype_ThenCredentialsAreNotFiltered() throws {
        class SecureVaultDelegate: MockSecureVaultManagerDelegate {
            override func secureVaultManager(_ manager: SecureVaultManager,
                                             promptUserToAutofillCredentialsForDomain domain: String,
                                             withAccounts accounts: [SecureVaultModels.WebsiteAccount],
                                             withTrigger trigger: AutofillUserScript.GetTriggerType,
                                             completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void) {
                XCTAssertEqual(accounts.count, 2, "Both accounts should be shown since the subType was `password`")
                completionHandler(accounts[1])
            }
        }

        self.secureVaultManagerDelegate = SecureVaultDelegate()
        self.manager.delegate = self.secureVaultManagerDelegate
        
        let triggerType = AutofillUserScript.GetTriggerType.userInitiated

        // account 1 (empty username)
        let domain = "domain.com"
        let username = ""
        let account = SecureVaultModels.WebsiteAccount(id: "1", title: nil, username: username, domain: domain, created: Date(), lastUpdated: Date())

        // account 2
        let username2 = "dax2"
        let account2 = SecureVaultModels.WebsiteAccount(id: "2", title: nil, username: username2, domain: domain, created: Date(), lastUpdated: Date())
        self.mockDatabaseProvider._accounts = [account, account2]

        // credential for the account
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8)!)
        let credentials2 = SecureVaultModels.WebsiteCredentials(account: account2, password: "password".data(using: .utf8)!)
        try self.testVault.storeWebsiteCredentials(credentials)
        try self.testVault.storeWebsiteCredentials(credentials2)

        let subType = AutofillUserScript.GetAutofillDataSubType.password
        let expect = expectation(description: #function)
        manager.autofillUserScript(mockAutofillUserScript, didRequestCredentialsForDomain: domain, subType: subType, trigger: triggerType) { credentials, provider, action in
            XCTAssertEqual(action, .fill)
            XCTAssertEqual(credentials!.password, "password".data(using: .utf8)!)
            XCTAssertEqual(credentials!.account.username, "dax2")
            expect.fulfill()
        }
        waitForExpectations(timeout: 0.1)
    }

    // MARK: - Test Utilities
    
    private func identity(id: Int64? = nil, name: (String, String, String), addressStreet: String?) -> SecureVaultModels.Identity {
        return SecureVaultModels.Identity(id: id,
                                          title: nil,
                                          created: Date(),
                                          lastUpdated: Date(),
                                          firstName: name.0,
                                          middleName: name.1,
                                          lastName: name.2,
                                          birthdayDay: nil,
                                          birthdayMonth: nil,
                                          birthdayYear: nil,
                                          addressStreet: addressStreet,
                                          addressStreet2: nil,
                                          addressCity: nil,
                                          addressProvince: nil,
                                          addressPostalCode: nil,
                                          addressCountryCode: nil,
                                          homePhone: nil,
                                          mobilePhone: nil,
                                          emailAddress: nil)
    }
    
    private func paymentMethod(id: Int64? = nil,
                               cardNumber: String,
                               cardholderName: String,
                               cvv: String,
                               month: Int,
                               year: Int) -> SecureVaultModels.CreditCard {
        return SecureVaultModels.CreditCard(id: id,
                                            title: nil,
                                            cardNumber: cardNumber,
                                            cardholderName: cardholderName,
                                            cardSecurityCode: cvv,
                                            expirationMonth: month,
                                            expirationYear: year)
    }
    
}

private class MockSecureVaultManagerDelegate: SecureVaultManagerDelegate {

    private(set) var promptedAutofillData: AutofillData?
    
    func secureVaultManagerIsEnabledStatus(_: SecureVaultManager) -> Bool {
        return true
    }
    
    func secureVaultManager(_: SecureVaultManager, promptUserToStoreAutofillData data: AutofillData) {
        self.promptedAutofillData = data
    }
    
    func secureVaultManager(_: SecureVaultManager,
                            promptUserToAutofillCredentialsForDomain domain: String,
                            withAccounts accounts: [SecureVaultModels.WebsiteAccount],
                            withTrigger trigger: AutofillUserScript.GetTriggerType,
                            completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void) {}
    
    func secureVaultManager(_: SecureVaultManager, didAutofill type: AutofillType, withObjectId objectId: String) {}
    
    func secureVaultManager(_: SecureVaultManager, didRequestAuthenticationWithCompletionHandler: @escaping (Bool) -> Void) {}
    
    func secureVaultInitFailed(_ error: SecureVaultError) {}
    
    func secureVaultManagerShouldAutomaticallyUpdateCredentialsWithoutUsername(_: SecureVaultManager) -> Bool {
        return true
    }

    func secureVaultManager(_: SecureVaultManager, didRequestCreditCardsManagerForDomain domain: String) {}

    func secureVaultManager(_: SecureVaultManager, didRequestIdentitiesManagerForDomain domain: String) {}

    func secureVaultManager(_: SecureVaultManager, didRequestPasswordManagerForDomain domain: String) {}
    
    func secureVaultManager(_: SecureVaultManager, didReceivePixel: AutofillUserScript.JSPixel) {}
    
}
