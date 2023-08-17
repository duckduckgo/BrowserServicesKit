//
//  EmailManagerTests.swift
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

import XCTest
@testable import BrowserServicesKit

enum EmailManagerTestEvent {
    case getAliasCallbackCalled
    case deleteAliasCalled
    case storeAliasCalled
    case storeTokenCalled
    case aliasRequestMade
}

var events = [EmailManagerTestEvent]()

class EmailManagerTests: XCTestCase {

    func getAutofillScript() -> AutofillUserScript {
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
        let privacyConfigManager = AutofillTestHelper.preparePrivacyConfig(embeddedConfig: embeddedConfig)
        let sourceProvider = DefaultAutofillSourceProvider(privacyConfigurationManager: privacyConfigManager,
                                                           properties: ContentScopeProperties(gpcEnabled: false,
                                                                                              sessionKey: "1234",
                                                                                              featureToggles: ContentScopeFeatureToggles.allTogglesOn))
        let userScript = AutofillUserScript(scriptSourceProvider: sourceProvider)
        return userScript
    }

    func testWhenGettingUserEmailAndUserIsSignedInThenEmailAddressIsValid() {
        let username = "dax"
        let storage = MockEmailManagerStorage()
        storage.mockUsername = username
        let emailManager = EmailManager(storage: storage)

        XCTAssertEqual(emailManager.userEmail, "\(username)@duck.com")
    }

    func testWhenGettingUserEmailAndUserIsNotSignedInThenNilIsReturned() {
        let storage = MockEmailManagerStorage()
        let emailManager = EmailManager(storage: storage)

        XCTAssertNil(emailManager.userEmail)
    }

    func testWhenGeneratingEmailAddressForAliasThenAliasHasCorrectFormat() {
        let storage = MockEmailManagerStorage()
        let emailManager = EmailManager(storage: storage)
        let generatedAddress = emailManager.emailAddressFor("test-alias")

        XCTAssertEqual(generatedAddress, "test-alias@duck.com")
    }

    func testWhenSignOutThenDeletesAllStorage() {
        let storage = MockEmailManagerStorage()
        let emailManager = EmailManager(storage: storage)

        let expect = expectation(description: "test")
        storage.deleteAuthenticationStateCallback = {
            expect.fulfill()
        }

        emailManager.signOut()
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testWhenRequestSignedInStatusThenReturnsCorrectStatus() {
        let storage = MockEmailManagerStorage()
        let emailManager = EmailManager(storage: storage)
        storage.mockUsername = "username"
        storage.mockToken = "token"

        let userScript = getAutofillScript()
        var status = emailManager.autofillUserScriptDidRequestSignedInStatus(userScript)
        XCTAssertTrue(status)

        storage.mockUsername = nil
        status = emailManager.autofillUserScriptDidRequestSignedInStatus(userScript)
        XCTAssertFalse(status)

        storage.mockUsername = "username"
        storage.mockToken = nil
        status = emailManager.autofillUserScriptDidRequestSignedInStatus(userScript)
        XCTAssertFalse(status)
    }

    func testWhenCallingGetAliasEmailWithAliasStoredThenAliasReturnedAndNewAliasFetched() {

        let expect = expectation(description: "test")
        let storage = storageForGetAliasTest(signedIn: true, storedAlias: true, fulfillOnFirstStorageEvent: true, expectationToFulfill: expect)
        let emailManager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.mockAliases = ["testAlias2", "testAlias3"]
        emailManager.requestDelegate = requestDelegate

        events.removeAll()

        // When an alias is stored
        // should call completion with stored alias
        // then delete alias
        // then there should be a request for a new alias
        // and it should store the new one
        let expectedEvents: [EmailManagerTestEvent] = [
            .getAliasCallbackCalled,
            .deleteAliasCalled,
            .aliasRequestMade,
            .storeAliasCalled
        ]

        emailManager.getAliasIfNeededAndConsume { alias, _ in
            XCTAssertEqual(alias, "testAlias1")
            events.append(.getAliasCallbackCalled)
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    func testWhenCallingGetAliasEmailWithNoAliasStoredThenAliasFetchedAndNewAliasFetched() {

        let expect = expectation(description: "test")
        let storage = storageForGetAliasTest(signedIn: true, storedAlias: false, fulfillOnFirstStorageEvent: false, expectationToFulfill: expect)
        let emailManager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.mockAliases = ["testAlias2", "testAlias3"]
        emailManager.requestDelegate = requestDelegate

        events.removeAll()

        // Test when no alias is stored
        // should make a request
        // call the callback
        // make a new request
        // and store the new alias

        let expectedEvents: [EmailManagerTestEvent] = [
            .aliasRequestMade,
            .storeAliasCalled,
            .getAliasCallbackCalled,
            .deleteAliasCalled,
            .aliasRequestMade,
            .storeAliasCalled
        ]

        emailManager.getAliasIfNeededAndConsume { alias, _ in
            XCTAssertEqual(alias, "testAlias2")
            events.append(.getAliasCallbackCalled)
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    func testWhenCallingGetAliasWhenSignedOutThenNoAliasReturned() {
        let expect = expectation(description: "test")
        let storage = storageForGetAliasTest(signedIn: false, storedAlias: false, fulfillOnFirstStorageEvent: false, expectationToFulfill: expect)
        let emailManager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.mockAliases = ["testAlias2", "testAlias3"]
        emailManager.requestDelegate = requestDelegate

        events.removeAll()

        let expectedEvents: [EmailManagerTestEvent] = [
            .getAliasCallbackCalled
        ]

        emailManager.getAliasIfNeededAndConsume { alias, error in
            XCTAssertNil(alias)
            XCTAssertEqual(error, .signedOut)
            events.append(.getAliasCallbackCalled)
            expect.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    func testWhenStoreTokenThenRequestForAliasMade() {
        let expect = expectation(description: "test")
        let storage = storageForGetAliasTest(signedIn: true, storedAlias: false, fulfillOnFirstStorageEvent: true, expectationToFulfill: expect)
        let emailManager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.mockAliases = ["testAlias2", "testAlias3"]
        emailManager.requestDelegate = requestDelegate

        events.removeAll()

        let expectedEvents: [EmailManagerTestEvent] = [
            .storeTokenCalled,
            .aliasRequestMade,
            .storeAliasCalled
        ]

        let userScript = getAutofillScript()

        emailManager.autofillUserScript(userScript, didRequestStoreToken: "token", username: "username", cohort: "internal_beta")

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    func testWhenRequestingUsernameAndAliasThenTheyAreReturned() {
        let expect = expectation(description: "test")
        let storage = storageForGetAliasTest(signedIn: true, storedAlias: false, fulfillOnFirstStorageEvent: true, expectationToFulfill: expect)
        let emailManager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.mockAliases = ["testAlias2", "testAlias3"]
        emailManager.requestDelegate = requestDelegate

        events.removeAll()

        let expectedEvents: [EmailManagerTestEvent] = [
            .aliasRequestMade,
            .storeAliasCalled
        ]

        let userScript = getAutofillScript()

        emailManager.autofillUserScriptDidRequestUsernameAndAlias(userScript) { username, alias, error in
            XCTAssertNil(error)
            XCTAssertEqual(username, "username")
            XCTAssertEqual(alias, "testAlias2")
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    func testWhenRequestingUserDataThenTheyAreReturned() {
        let expect = expectation(description: "test")
        let storage = storageForGetAliasTest(signedIn: true, storedAlias: false, fulfillOnFirstStorageEvent: true, expectationToFulfill: expect)
        storage.mockToken = "token"
        let emailManager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.mockAliases = ["testAlias2", "testAlias3"]
        emailManager.requestDelegate = requestDelegate

        events.removeAll()

        let expectedEvents: [EmailManagerTestEvent] = [
            .aliasRequestMade,
            .storeAliasCalled
        ]

        let userScript = getAutofillScript()

        emailManager.autofillUserScriptDidRequestUserData(userScript) { username, alias, token, error in
            XCTAssertNil(error)
            XCTAssertEqual(username, "username")
            XCTAssertEqual(token, "token")
            XCTAssertEqual(alias, "testAlias2")
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    private func storageForGetAliasTest(signedIn: Bool,
                                        storedAlias: Bool,
                                        fulfillOnFirstStorageEvent: Bool,
                                        expectationToFulfill: XCTestExpectation) -> MockEmailManagerStorage {

        let storage = MockEmailManagerStorage()

        if signedIn {
            storage.mockUsername = "username"
            storage.mockToken = "testToken"
        }

        if storedAlias {
            storage.mockAlias = "testAlias1"
        }

        storage.deleteAliasCallback = {
            events.append(.deleteAliasCalled)
        }

        storage.storeTokenCallback = { _, _, _ in
            events.append(.storeTokenCalled)
        }

        var isFirstStorage = true
        storage.storeAliasCallback = { alias in
            events.append(.storeAliasCalled)
            if isFirstStorage {
                XCTAssertEqual(alias, "testAlias2")
                isFirstStorage = false
                if fulfillOnFirstStorageEvent {
                    expectationToFulfill.fulfill()
                }
            } else {
                XCTAssertEqual(alias, "testAlias3")
                expectationToFulfill.fulfill()
            }
        }

        return storage
    }

    func testWhenGettingLastUseDateFirstTimeThenEmptyValueIsReturned() {
        let storage = MockEmailManagerStorage()
        let emailManager = EmailManager(storage: storage)

        XCTAssertEqual(emailManager.lastUseDate, "")
    }

    func testWhenSettingLastUseDateThenValueIsReturned() {

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York")

        let dateStoredExpectation = expectation(description: "Date Stored")

        let storage = MockEmailManagerStorage()
        storage.storeLastUseDateCallback = { dateString in
            dateStoredExpectation.fulfill()
            XCTAssertNotNil(dateFormatter.date(from: dateString))
        }
        let emailManager = EmailManager(storage: storage)
        emailManager.updateLastUseDate()

        wait(for: [dateStoredExpectation], timeout: 1.0)
    }

    func testWhenGettingUsername_AndKeychainAccessFails_ThenRequestDelegateIsCalled() {
        let username = "dax"
        let storage = MockEmailManagerStorage()
        storage.mockError = .keychainLookupFailure(errSecInternalError)
        storage.mockUsername = username
        let emailManager = EmailManager(storage: storage)

        let requestDelegate = MockEmailManagerRequestDelegate()
        emailManager.requestDelegate = requestDelegate

        XCTAssertNil(emailManager.userEmail)
        XCTAssertEqual(requestDelegate.keychainAccessErrorAccessType, .getUsername)
        XCTAssertEqual(requestDelegate.keychainAccessError, .keychainLookupFailure(errSecInternalError))
    }

}

class MockEmailManagerRequestDelegate: EmailManagerRequestDelegate {
    var activeTask: URLSessionTask?
    var mockAliases: [String] = []
    var waitlistTimestamp: Int = 1

    // swiftlint:disable function_parameter_count
    func emailManager(_ emailManager: EmailManager, requested url: URL, method: String, headers: [String: String], parameters: [String: String]?, httpBody: Data?, timeoutInterval: TimeInterval) async throws -> Data {
        switch url.absoluteString {
        case EmailUrls.Url.emailAlias: return try processMockAliasRequest().get()
        default: fatalError("\(#file): Unsupported URL passed to mock request delegate: \(url)")
        }
    }
    // swiftlint:enable function_parameter_count

    var keychainAccessErrorAccessType: EmailKeychainAccessType?
    var keychainAccessError: EmailKeychainAccessError?

    func emailManagerKeychainAccessFailed(accessType: EmailKeychainAccessType, error: EmailKeychainAccessError) {
        keychainAccessErrorAccessType = accessType
        keychainAccessError = error
    }

    private func processMockAliasRequest() -> Result<Data, Error> {
        events.append(.aliasRequestMade)

        if mockAliases.first != nil {
            let alias = mockAliases.removeFirst()
            let jsonString = "{\"address\":\"\(alias)\"}"
            let data = jsonString.data(using: .utf8)!
            return .success(data)
        } else {
            return .failure(AliasRequestError.noDataError)
        }
    }

}

class MockEmailManagerStorage: EmailManagerStorage {

    var mockError: EmailKeychainAccessError?

    var mockUsername: String?
    var mockToken: String?
    var mockAlias: String?
    var mockCohort: String?
    var mockLastUseDate: String?

    var storeTokenCallback: ((String, String, String?) -> Void)?
    var storeAliasCallback: ((String) -> Void)?
    var storeLastUseDateCallback: ((String) -> Void)?
    var deleteAliasCallback: (() -> Void)?
    var deleteAuthenticationStateCallback: (() -> Void)?
    var deleteWaitlistStateCallback: (() -> Void)?

    func getUsername() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockUsername
    }

    func getToken() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockToken
    }

    func getAlias() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockAlias
    }

    func getCohort() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockCohort
    }

    func getLastUseDate() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockLastUseDate
    }

    func store(token: String, username: String, cohort: String?) throws {
        storeTokenCallback?(token, username, cohort)
    }

    func store(alias: String) throws {
        storeAliasCallback?(alias)
    }

    func store(lastUseDate: String) throws {
        storeLastUseDateCallback?(lastUseDate)
    }

    func deleteAlias() {
        deleteAliasCallback?()
    }

    func deleteAuthenticationState() {
        deleteAuthenticationStateCallback?()
    }

    func deleteWaitlistState() {
        deleteWaitlistStateCallback?()
    }

}
