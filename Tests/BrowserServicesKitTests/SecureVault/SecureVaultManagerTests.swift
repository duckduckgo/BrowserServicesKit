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
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: nil, creditCard: nil, trigger: nil)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNil(entries.creditCard)
    }
    
    func testWhenGettingExistingEntries_AndAutofillCreditCardWasProvided_AndNoMatchingCreditCardExists_ThenReturnValueIncludesCard() throws {
        let card = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 2022)

        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: nil, creditCard: card, trigger: nil)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNotNil(entries.creditCard)
        XCTAssertTrue(entries.creditCard!.hasAutofillEquality(comparedTo: card))
    }
    
    func testWhenGettingExistingEntries_AndAutofillCreditCardWasProvided_AndMatchingCreditCardExists_ThenReturnValueIsNil() throws {
        let card = paymentMethod(id: 1, cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 2022)
        try self.testVault.storeCreditCard(card)

        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: nil, creditCard: card, trigger: nil)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNil(entries.creditCard)
    }
    
    func testWhenGettingExistingEntries_AndAutofillIdentityWasProvided_AndNoMatchingIdentityExists_ThenReturnValueIncludesIdentity() throws {
        let identity = identity(name: ("First", "Middle", "Last"), addressStreet: "Address Street")
        
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: identity, credentials: nil, creditCard: nil, trigger: nil)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.creditCard)
        XCTAssertNotNil(entries.identity)
        XCTAssertTrue(entries.identity!.hasAutofillEquality(comparedTo: identity))
    }
    
    func testWhenGettingExistingEntries_AndAutofillIdentityWasProvided_AndMatchingIdentityExists_ThenReturnValueIsNil() throws {
        let identity = identity(id: 1, name: ("First", "Middle", "Last"), addressStreet: "Address Street")
        try self.testVault.storeIdentity(identity)

        let autofillData = AutofillUserScript.DetectedAutofillData(identity: identity, credentials: nil, creditCard: nil, trigger: nil)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNil(entries.creditCard)
    }

    // MARK: - AutofillSecureVaultDelegate Tests
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

    // MARK: SecureVaultManager+AutofillSecureVaultDelegate Tests

    // When generating a username in an empty form, a partial login (no password) should be created
    // Then, when a password is generated, the partial login should be updated
    func testWhenGeneratingUsernameFirstThenPassword_ThenDataIsAutosaved() {

        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xdt7r90@duck.com", password: "", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        var credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "xdt7r90@duck.com")
        XCTAssertEqual(credentials?.password, Data())

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xdt7r90@duck.com", password: "xtewq311", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .passwordGeneration)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "xdt7r90@duck.com")
        XCTAssertEqual(credentials?.password, Data("xtewq311".utf8))

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xdas871@duck.com", password: "xtewq311", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "xdas871@duck.com")
        XCTAssertEqual(credentials?.password, Data("xtewq311".utf8))

    }

    // When generating a password in an empty form, a partial login (no user) should be created
    // When generating a username in the same form, the partial login should be updated
    func testWhenGeneratingPasswordFirstThenUsername_ThenDataIsAutosaved() {

        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "", password: "sdfljk23", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .passwordGeneration)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        var credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "")
        XCTAssertEqual(credentials?.password, Data("sdfljk23".utf8))

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "a23x123@duck.com", password: "", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "a23x123@duck.com")
        XCTAssertEqual(credentials?.password, Data("sdfljk23".utf8))

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xdas879@duck.com", password: "sdfljk23", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "xdas879@duck.com")
        XCTAssertEqual(credentials?.password, Data("sdfljk23".utf8))

    }

    // When generating a user and manually typing a password, credentials should be saved automatically
    func testWhenGeneratingUsernameWithManualPassword_ThenDataisAutosaved() {

        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xdt7r91@duck.com", password: "", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xdt7r91@duck.com", password: "09akjyuasd", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        let credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "xdt7r91@duck.com")
        XCTAssertEqual(credentials?.password, Data("09akjyuasd".utf8))

    }

    // When generating a password and manually typing a user, credentials should be saved
    func testWhenGeneratingPasswordWithManualUsername_ThenDataIsAutosaved() {

        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "", password: "DC$z5SLYo47iDzwq1ZFV", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .passwordGeneration)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "l9rb3zxh@example.com", password: "DC$z5SLYo47iDzwq1ZFV", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        let credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "l9rb3zxh@example.com")
        XCTAssertEqual(credentials?.password, Data("DC$z5SLYo47iDzwq1ZFV".utf8))

    }

    // When generating a password and then generating a non 'autogenerated' username, such as the personal email
    // address.  [Personal email addresses are not marked autogenerated: true]
    func testWhenGeneratingPasswordWithParsonalEmailUsername_ThenDataIsAutosaved() {

        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "", password: "-8!4KNW!_RJN.a-ADaFpZG", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .passwordGeneration)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "aslkrdiu11@duck.com", password: "-8!4KNW!_RJN.a-ADaFpZG", autogenerated: false)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "aslkrdiu11@duck.com", password: "-8!4KNW!_RJN.a-ADaFpZG", autogenerated: false)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        let credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "aslkrdiu11@duck.com")
        XCTAssertEqual(credentials?.password, Data("-8!4KNW!_RJN.a-ADaFpZG".utf8))

    }

    // When generating a password and then changing it to something else, credentials should not be autosaved (prompt should be presented instead)
    func testWhenGeneratedPasswordIsManuallyChanged_ThenDataIsNotAutosaved() {

        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "", password: "wVvDKpan!kR7uAyPZ4", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .passwordGeneration)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "", password: "QNKs6k4a-axYX@aRQW", autogenerated: false)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .passwordGeneration)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        // Autofill prompted data tests
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "QNKs6k4a@example.com", password: "QNKs6k4a-axYX@aRQW", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        let entries = try? manager.existingEntries(for: "fill.dev", autofillData: incomingData)
        XCTAssertEqual(entries?.credentials?.account.username, "QNKs6k4a@example.com")
        XCTAssertEqual(entries?.credentials?.password, Data("QNKs6k4a-axYX@aRQW".utf8))

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "QNKs6k4a@example.com", password: "QNKs6k4a-axYX@aRQW", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        XCTAssertNotNil(secureVaultManagerDelegate.promptedAutofillData)
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.account.username, "QNKs6k4a@example.com")
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.password, Data("QNKs6k4a-axYX@aRQW".utf8))

    }

    // When generating an email and then changing to personal duck address input, credentials should not be autosaved (prompt should be presented instead)    
    func testWhenGeneratedUsernameIsChangedToPersonalDuckAddress_ThenDataIsNotAutosaved() {
        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xkaaka99@duck.com", password: "", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        // Email should be saved
        let credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username , "xkaaka99@duck.com")
        XCTAssertEqual(credentials?.password ,  Data("".utf8))        

        // Select Private Email address and submit        
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "john1@duck.com", password: "", autogenerated: false)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "john1@duck.com", password: "QNKs6k4a-axYX@aRQW", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        let entries = try? manager.existingEntries(for: "fill.dev", autofillData: incomingData)
        
        // Confirm autofill entries are present
        XCTAssertEqual(entries?.credentials?.account.username, "john1@duck.com")
        XCTAssertEqual(entries?.credentials?.password, Data("QNKs6k4a-axYX@aRQW".utf8))

        // Confirm data prompt
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "john1@duck.com", password: "QNKs6k4a-axYX@aRQW", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        // Prompted data should be there
        XCTAssertNotNil(secureVaultManagerDelegate.promptedAutofillData)
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.account.username, "john1@duck.com")
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.password, Data("QNKs6k4a-axYX@aRQW".utf8))
        
    }
    
    // When generating an email and then changing to manual input, credentials should not be autosaved (prompt should be presented instead)    
    func testWhenGeneratedUsernameIsChangedToManualInput_ThenDataIsNotAutosaved() {
        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "akla11@duck.com", password: "", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)
        
        // Email should be saved
        let credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username , "akla11@duck.com")
        XCTAssertEqual(credentials?.password ,  Data("".utf8))        
        
        // Autofill prompted data tests
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "example@duck.com", password: "QNKs6k212aYX@aRQW", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        let entries = try? manager.existingEntries(for: "fill.dev", autofillData: incomingData)
        XCTAssertEqual(entries?.credentials?.account.username, "example@duck.com")
        XCTAssertEqual(entries?.credentials?.password, Data("QNKs6k212aYX@aRQW".utf8))
        
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "john1@duck.com", password: "QNKs6k4a-axYX@aRQW", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)
       
        let creds = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertNil(creds)
        
        // Prompted data should be there
        XCTAssertNotNil(secureVaultManagerDelegate.promptedAutofillData)
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.account.username, "john1@duck.com")
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.password, Data("QNKs6k4a-axYX@aRQW".utf8))
        
        
    }
    
    // When generating an email and then changing to manual input, credentials should not be autosaved (prompt should be presented instead)    
    func testWhenGeneratedUsernameIsManuallyChanged_ThenDataIsNotAutosaved() {
        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xkaaka99@duck.com", password: "", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)
        
        // Autofill prompted data tests
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "john1@duck.com", password: "QNKs6k4a-axYX@aRQW", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        let entries = try? manager.existingEntries(for: "fill.dev", autofillData: incomingData)
        XCTAssertEqual(entries?.credentials?.account.username, "john1@duck.com")
        XCTAssertEqual(entries?.credentials?.password, Data("QNKs6k4a-axYX@aRQW".utf8))
        
        // Submit the form
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "john1@duck.com", password: "QNKs6k4a-axYX@aRQW", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)
        
        // No data should be saved
        let credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertNil(credentials)
        
        // Prompted data should be there
        XCTAssertNotNil(secureVaultManagerDelegate.promptedAutofillData)
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.account.username, "john1@duck.com")
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.password, Data("QNKs6k4a-axYX@aRQW".utf8))
                
        
    }

    // When generating and entering a manual password, then deleting the automatically saved login
    // and using a manually entered email afterwards, no data should be saved
    func testWhenUsingGeneratedUserNameAndThenManualInputUsername_ThenDataIsNotAutoSaved() {

        // Create a login item via a generated username and manual password
        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xdt7r711@duck.com", password: "", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "xdt7r711@duck.com", password: "epWFZ6!xowA-s2aZw7", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        // Delete the created login
        var credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "xdt7r711@duck.com")
        XCTAssertEqual(credentials?.password, Data("epWFZ6!xowA-s2aZw7".utf8))

        try? testVault?.deleteWebsiteCredentialsFor(accountId: 1)
        credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertNil(credentials)

        // Use a manually entered username (or private email address)
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "daniel@duck.com", password: "", autogenerated: false)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .emailProtection)

        // No data should be saved
        credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertNil(credentials)

    }

    // When using a generated password, then changing it to something different and typing a username
    // The prompted data should include the newly entered username and passwords
    func testWhenUsingGeneratedPasswordThenManuallyChanged_ThenPromptedDataIsCorrect() {

        // Save a password
        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "", password: "sAWLzqYHrC!J7QPCfw", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .passwordGeneration)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)

        // Create mocked Autofill Data
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "aklasd891@example.com", password: "uJTapczmX9ReZ!4wMk", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)        
        
        let entries = try? manager.existingEntries(for: "fill.dev", autofillData: incomingData)
        XCTAssertEqual(entries?.credentials?.account.username, "aklasd891@example.com")
        XCTAssertEqual(entries?.credentials?.password, Data("uJTapczmX9ReZ!4wMk".utf8))
    }
        
    // When the user generates a pasword and there is a username present from the autofill script, it should be automatically saved too
    func testWhenGeneratingAPassword_ThenUsernameShouldBeSavedIfPresent() {
        let incomingCredentials = AutofillUserScript.IncomingCredentials(username: "asdlkj11@example.com", password: "sAWLzqYHrC!J7QPCfw", autogenerated: true)
        let incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .passwordGeneration)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)
        
        let credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "asdlkj11@example.com")
        XCTAssertEqual(credentials?.password, Data("sAWLzqYHrC!J7QPCfw".utf8))
    }
    
    // When submitting a form that never had autogenerated data, a prompt is shown
    func testWhenEnteringManualUsernameAndPassword_ThenDataIsSaved() {
        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "asdlkj12@example.com", password: "sAWLzqYHrC!J1assCfw", autogenerated: false)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)
        
        // Create mocked Autofill Data
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "asdlkj12@example.com", password: "sAWLzqYHrC!J1assCfw", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)        
        
        let entries = try? manager.existingEntries(for: "fill.dev", autofillData: incomingData)
        XCTAssertEqual(entries?.credentials?.account.username, "asdlkj12@example.com")
        XCTAssertEqual(entries?.credentials?.password, Data("sAWLzqYHrC!J1assCfw".utf8))
    }
    
    // When autosaving credentials for one site, and the using the same username in other site, data should not be automatically saved
    func testWhenSavingCredentialsAutomatically_PartialAccountShouldBeCleared() {
        var incomingCredentials = AutofillUserScript.IncomingCredentials(username: "aqqalkj1@example.com", password: "9dd6Gs*4..G92-hVAs", autogenerated: true)
        var incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .passwordGeneration)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)
        
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "aqqalkj1@example.com", password: "9dd6Gs*4..G92-hVAs", autogenerated: true)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "fill.dev", data: incomingData)
        
        // Credentials should be saved automatically
        var credentials = try? testVault?.websiteCredentialsFor(accountId: 1)
        XCTAssertEqual(credentials?.account.username, "aqqalkj1@example.com")
        XCTAssertEqual(credentials?.password, Data("9dd6Gs*4..G92-hVAs".utf8))
        
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "aqqalkj1@example.com", password: "TU2qp_HDADVGjfYh@Y", autogenerated: false)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)
        manager.autofillUserScript(mockAutofillUserScript, didRequestStoreDataForDomain: "profile.theguardian.com", data: incomingData)
        
        // Credentials should NOT saved automatically
        credentials = try? testVault?.websiteCredentialsFor(accountId: 2)
        XCTAssertNil(credentials)
        
        // Create mocked Autofill Data
        incomingCredentials = AutofillUserScript.IncomingCredentials(username: "aqqalkj1@example.com", password: "TU2qp_HDADVGjfYh@Y", autogenerated: false)
        incomingData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: incomingCredentials, creditCard: nil, trigger: .formSubmission)        
        
        let entries = try? manager.existingEntries(for: "fill.dev", autofillData: incomingData)
        XCTAssertEqual(entries?.credentials?.account.username, "aqqalkj1@example.com")
        XCTAssertEqual(entries?.credentials?.password, Data("TU2qp_HDADVGjfYh@Y".utf8))
        
        // Prompted data should be there
        XCTAssertNotNil(secureVaultManagerDelegate.promptedAutofillData)
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.account.username, "aqqalkj1@example.com")
        XCTAssertEqual(secureVaultManagerDelegate.promptedAutofillData?.credentials?.password, Data("TU2qp_HDADVGjfYh@Y".utf8))
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

    func secureVaultManager(_: SecureVaultManager,
                            promptUserToStoreAutofillData data: AutofillData,
                            withTrigger trigger: AutofillUserScript.GetTriggerType?) {
        self.promptedAutofillData = data
    }

    func secureVaultManager(_: SecureVaultManager,
                            promptUserToAutofillCredentialsForDomain domain: String,
                            withAccounts accounts: [SecureVaultModels.WebsiteAccount],
                            withTrigger trigger: AutofillUserScript.GetTriggerType,
                            completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void) {}

    func secureVaultManager(_: BrowserServicesKit.SecureVaultManager, promptUserWithGeneratedPassword password: String, completionHandler: @escaping (Bool) -> Void) {}

    
    func secureVaultManager(_: SecureVaultManager, didAutofill type: AutofillType, withObjectId objectId: String) {}
    
    func secureVaultManager(_: SecureVaultManager, didRequestAuthenticationWithCompletionHandler: @escaping (Bool) -> Void) {}
    
    func secureVaultInitFailed(_ error: SecureVaultError) {}

    func secureVaultManager(_: SecureVaultManager, didRequestCreditCardsManagerForDomain domain: String) {}

    func secureVaultManager(_: SecureVaultManager, didRequestIdentitiesManagerForDomain domain: String) {}

    func secureVaultManager(_: SecureVaultManager, didRequestPasswordManagerForDomain domain: String) {}

    func secureVaultManager(_: SecureVaultManager, didReceivePixel: AutofillUserScript.JSPixel) {}
    
}
