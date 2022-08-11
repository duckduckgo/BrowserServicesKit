//
//  AutofillVaultUserScriptTests.swift
//  DuckDuckGo
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
import WebKit
@testable import BrowserServicesKit

// swiftlint:disable type_body_length
// swiftlint:disable file_length

class AutofillVaultUserScriptTests: XCTestCase {
    
    let userScript: AutofillUserScript = {
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
        return AutofillUserScript(scriptSourceProvider: sourceProvider)
    }()
    let userContentController = WKUserContentController()

    var encryptedMessagingParams: [String: Any] {
        return [
            "messageHandling": [
                "iv": Array(repeating: UInt8(1), count: 32),
                "key": Array(repeating: UInt8(1), count: 32),
                "secret": userScript.generatedSecret,
                "methodName": "test-methodName"
            ]
        ]
    }

    @available(macOS 11, iOS 14, *)
    func testWhenAccountsForDomainRequested_ThenDelegateCalled() {
        class GetAccountsDelegate: MockSecureVaultDelegate {
            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestAccountsForDomain domain: String,
                                             completionHandler: @escaping ([SecureVaultModels.WebsiteAccount]) -> Void) {
                completionHandler([
                    SecureVaultModels.WebsiteAccount(id: 1, username: "1@example.com", domain: "domain", created: Date(), lastUpdated: Date()),
                    SecureVaultModels.WebsiteAccount(id: 2, username: "2@example.com", domain: "domain", created: Date(), lastUpdated: Date())
                ])
            }
        }

        let delegate = GetAccountsDelegate()
        userScript.vaultDelegate = delegate

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetAccounts", body: encryptedMessagingParams, webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotNil($0)
            XCTAssertNil($1)

            let data = ($0 as? String)?.data(using: .utf8)
            let response = try? JSONDecoder().decode(AutofillUserScript.RequestVaultAccountsResponse.self, from: data!)
            XCTAssertEqual(response?.success.count, 2)

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)
   }

    @available(macOS 11, iOS 14, *)
    func testWhenCredentialForAccountRequested_ThenDelegateCalled() {
        class GetCredentialsDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestCredentialsForAccount accountId: Int64,
                                             completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?) -> Void) {

                completionHandler(.init(account: .init(id: accountId,
                                                       username: "1@example.com",
                                                       domain: "example.com",
                                                       created: Date(),
                                                       lastUpdated: Date()),
                                        password: "password".data(using: .utf8)!))

            }

        }

        let randomAccountId = Int.random(in: 0 ..< Int.max) // JS will come through as a Int rather than Int64

        let delegate = GetCredentialsDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["id"] = "\(randomAccountId)"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetAutofillCredentials", body: body, webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotNil($0)
            XCTAssertNil($1)

            let data = ($0 as? String)?.data(using: .utf8)
            let response = try? JSONDecoder().decode(AutofillUserScript.RequestVaultCredentialsForAccountResponse.self, from: data!)
            XCTAssertEqual(Int64(response!.success.id), Int64(randomAccountId))

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    @available(macOS 11, iOS 14, *)
    func testWhenStoreDataCalled_ThenDelegateIsCalled() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["credentials"] = ["username": "username@example.com", "password": "password"]

        let mockWebView = MockWebView()
        let message = MockAutofillMessage(name: "pmHandlerStoreData", body: body,
                                          host: "example.com", webView: mockWebView)

        userScript.processMessage(userContentController, didReceive: message)

        XCTAssertEqual(delegate.lastDomain, "example.com")
        XCTAssertEqual(delegate.lastUsername, "username@example.com")
        XCTAssertEqual(delegate.lastPassword, "password")
    }

    @available(macOS 11, iOS 14, *)
    func testWhenCreditCardForIdIsRequested_ThenDelegateIsCalled() {

        class GetCreditCardDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestCreditCardWithId creditCardId: Int64,
                                             completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {

                completionHandler(.init(id: creditCardId,
                                        title: "Mock Card",
                                        cardNumber: "1234123412341234",
                                        cardholderName: "Dax",
                                        cardSecurityCode: "123",
                                        expirationMonth: 11,
                                        expirationYear: 2021))

            }

        }

        let randomCardId = Int.random(in: 0 ..< Int.max)

        let delegate = GetCreditCardDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["id"] = "\(randomCardId)"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetCreditCard", body: body, webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotNil($0)
            XCTAssertNil($1)

            let data = ($0 as? String)?.data(using: .utf8)
            let response = try? JSONDecoder().decode(AutofillUserScript.RequestAutoFillCreditCardResponse.self, from: data!)
            XCTAssertEqual(response?.success.id, Int64(randomCardId))

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)

    }

    @available(macOS 11, iOS 14, *)
    func testWhenIdentityForIdIsRequested_ThenDelegateIsCalled() {

        class GetCreditCardDelegate: MockSecureVaultDelegate {

            override func autofillUserScript(_: AutofillUserScript,
                                             didRequestIdentityWithId identityId: Int64,
                                             completionHandler: @escaping (SecureVaultModels.Identity?) -> Void) {
                completionHandler(.init(id: identityId,
                                        title: "Identity",
                                        created: Date(),
                                        lastUpdated: Date(),
                                        firstName: "Dax",
                                        middleName: nil,
                                        lastName: nil,
                                        birthdayDay: 1,
                                        birthdayMonth: 2,
                                        birthdayYear: 3,
                                        addressStreet: nil,
                                        addressCity: nil,
                                        addressProvince: nil,
                                        addressPostalCode: nil,
                                        addressCountryCode: nil,
                                        homePhone: nil,
                                        mobilePhone: nil,
                                        emailAddress: nil))
            }

        }

        let randomIdentityId = Int.random(in: 0 ..< Int.max)

        let delegate = GetCreditCardDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["id"] = "\(randomIdentityId)"

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "pmHandlerGetIdentity", body: body, webView: mockWebView)

        let expect = expectation(description: #function)
        userScript.userContentController(userContentController, didReceive: message) {
            XCTAssertNotNil($0)
            XCTAssertNil($1)

            let data = ($0 as? String)?.data(using: .utf8)
            let response = try? JSONDecoder().decode(AutofillUserScript.RequestAutoFillIdentityResponse.self, from: data!)
            XCTAssertEqual(response?.success.id, Int64(randomIdentityId))

            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0)

    }

    func testWhenShowPasswordManagementUIIsCalled_ThenDelegateIsCalled() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        let mockWebView = MockWebView()
        let message = MockAutofillMessage(name: "pmHandlerOpenManagePasswords", body: encryptedMessagingParams,
                                          host: "example.com", webView: mockWebView)

        userScript.processMessage(userContentController, didReceive: message)

        XCTAssertEqual(delegate.lastDomain, "example.com")
    }

    func testWhenShowCardManagementUIIsCalled_ThenDelegateIsCalled() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        let mockWebView = MockWebView()
        let message = MockAutofillMessage(name: "pmHandlerOpenManageCreditCards", body: encryptedMessagingParams,
                                          host: "example.com", webView: mockWebView)

        userScript.processMessage(userContentController, didReceive: message)

        XCTAssertEqual(delegate.lastDomain, "example.com")
    }

    func testWhenShowIdentityManagementUIIsCalled_ThenDelegateIsCalled() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        let mockWebView = MockWebView()
        let message = MockAutofillMessage(name: "pmHandlerOpenManageIdentities", body: encryptedMessagingParams,
                                          host: "example.com", webView: mockWebView)

        userScript.processMessage(userContentController, didReceive: message)

        XCTAssertEqual(delegate.lastDomain, "example.com")
    }
    
    func testWhenInitializingAutofillData_WhenCredentialsAreProvidedWithoutAUsername_ThenAutofillDataIsStillInitialized() {
        let password = "password"
        let detectedAutofillData = [
            "credentials": [
                "password": password
            ]
        ]
        
        let autofillData = AutofillUserScript.DetectedAutofillData(dictionary: detectedAutofillData)
        
        XCTAssertNil(autofillData.creditCard)
        XCTAssertNil(autofillData.identity)
        XCTAssertNotNil(autofillData.credentials)
        
        XCTAssertEqual(autofillData.credentials?.username, nil)
        XCTAssertEqual(autofillData.credentials?.password, password)
    }
    
    func testWhenInitializingAutofillData_WhenCredentialsAreProvidedWithAUsername_ThenAutofillDataIsStillInitialized() {
        let username = "username"
        let password = "password"
        
        let detectedAutofillData = [
            "credentials": [
                "username": username,
                "password": password
            ]
        ]
        
        let autofillData = AutofillUserScript.DetectedAutofillData(dictionary: detectedAutofillData)
        
        XCTAssertNil(autofillData.creditCard)
        XCTAssertNil(autofillData.identity)
        XCTAssertNotNil(autofillData.credentials)
        
        XCTAssertEqual(autofillData.credentials?.username, username)
        XCTAssertEqual(autofillData.credentials?.password, password)
    }

    func testWhenGetAutofilldataIsCall_ThenMainAndSubtypesAreUsed() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["mainType"] = "credentials"
        body["subType"] = "username"
        body["trigger"] = "userInitiated"

        let mockWebView = MockWebView()
        let message = MockAutofillMessage(name: "getAutofillData", body: body, host: "example.com", webView: mockWebView)

        userScript.processMessage(userContentController, didReceive: message)
        
        let predicate = NSPredicate(block: { _, _ -> Bool in
            return !delegate.receivedCallbacks.isEmpty
        })
        
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: delegate.receivedCallbacks)
        
        wait(for: [expectation], timeout: 5)
        
        XCTAssertEqual(delegate.lastSubtype, AutofillUserScript.GetAutofillDataSubType.username)
    }

    func testWhenGetAutofilldataIsCalledWithUnknownMainType_ThenTheMessageIsIgnored() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["mainType"] = "creditCards" // <- unsupported main type
        body["subType"] = "username"
        body["trigger"] = "userInitiated"

        let mockWebView = MockWebView()
        let message = MockAutofillMessage(name: "getAutofillData", body: body, host: "example.com", webView: mockWebView)

        userScript.processMessage(userContentController, didReceive: message)
        XCTAssertNil(delegate.lastSubtype)
    }

    func testWhenGetAutofilldataIsCalledWithUnknownSubType_ThenTheMessageIsIgnored() {

        let delegate = MockSecureVaultDelegate()
        userScript.vaultDelegate = delegate

        var body = encryptedMessagingParams
        body["mainType"] = "credentials"
        body["subType"] = "anything_else"
        body["trigger"] = "userInitiated"

        let mockWebView = MockWebView()
        let message = MockAutofillMessage(name: "getAutofillData", body: body, host: "example.com", webView: mockWebView)

        userScript.processMessage(userContentController, didReceive: message)
        XCTAssertNil(delegate.lastSubtype)
    }
}

class MockSecureVaultDelegate: AutofillSecureVaultDelegate {

    enum CallbackType {
        case didRequestPasswordManagerForDomain
        case didRequestStoreDataForDomain
        case didRequestAccountsForDomain
        case didRequestCredentialsForDomain
    }

    var receivedCallbacks: [CallbackType] = []
    
    var lastDomain: String?
    var lastUsername: String?
    var lastPassword: String?
    var lastSubtype: AutofillUserScript.GetAutofillDataSubType?

    func autofillUserScript(_: AutofillUserScript, didRequestPasswordManagerForDomain domain: String) {
        lastDomain = domain
        receivedCallbacks.append(.didRequestPasswordManagerForDomain)
    }

    func autofillUserScript(_: AutofillUserScript, didRequestStoreDataForDomain domain: String, data: AutofillUserScript.DetectedAutofillData) {
        lastDomain = domain
        lastUsername = data.credentials?.username
        lastPassword = data.credentials?.password
        receivedCallbacks.append(.didRequestStoreDataForDomain)
    }

    func autofillUserScript(_: AutofillUserScript,
                            didRequestAccountsForDomain domain: String,
                            completionHandler: @escaping ([SecureVaultModels.WebsiteAccount]) -> Void) {
        lastDomain = domain
        receivedCallbacks.append(.didRequestAccountsForDomain)
    }

    func autofillUserScript(_: AutofillUserScript,
                            didRequestCredentialsForAccount accountId: Int64,
                            completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?) -> Void) {
    }

    func autofillUserScript(_: AutofillUserScript,
                            didRequestAutoFillInitDataForDomain domain: String,
                            completionHandler: @escaping ([SecureVaultModels.WebsiteAccount],
                                                          [SecureVaultModels.Identity],
                                                          [SecureVaultModels.CreditCard]) -> Void) {
    }

    func autofillUserScript(_: AutofillUserScript,
                            didRequestCreditCardWithId creditCardId: Int64,
                            completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
    }

    func autofillUserScript(_: AutofillUserScript,
                            didRequestIdentityWithId identityId: Int64,
                            completionHandler: @escaping (SecureVaultModels.Identity?) -> Void) {
    }

    func autofillUserScript(_ script: AutofillUserScript,
                            didRequestCredentialsForDomain: String,
                            subType: AutofillUserScript.GetAutofillDataSubType,
                            trigger: AutofillUserScript.GetTriggerType,
                            completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?, RequestVaultCredentialsAction) -> Void) {
        lastSubtype = subType
        receivedCallbacks.append(.didRequestCredentialsForDomain)
        
        completionHandler(nil, .none)
    }
}

struct NoneEncryptingEncrypter: AutofillEncrypter {

    func encryptReply(_ reply: String, key: [UInt8], iv: [UInt8]) throws -> (ciphertext: Data, tag: Data) {
        return (reply.data(using: .utf8)!, Data())
    }

}

// swiftlint:enable type_body_length
// swiftlint:enable file_length
