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
    case joinWaitlistRequestMade
    case waitlistStatusRequestMade
    case waitlistInviteCodeRequestMade
    case storeWaitlistTokenCalled
    case storeWaitlistTimestampCalled
    case storeWaitlistInviteCodeCalled
}

var events = [EmailManagerTestEvent]()

class EmailManagerTests: XCTestCase {

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

        var status = emailManager.autofillUserScriptDidRequestSignedInStatus(AutofillUserScript())
        XCTAssertTrue(status)

        storage.mockUsername = nil
        status = emailManager.autofillUserScriptDidRequestSignedInStatus(AutofillUserScript())
        XCTAssertFalse(status)

        storage.mockUsername = "username"
        storage.mockToken = nil
        status = emailManager.autofillUserScriptDidRequestSignedInStatus(AutofillUserScript())
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
        
        emailManager.autofillUserScript(AutofillUserScript(), didRequestStoreToken: "token", username: "username", cohort: "internal_beta")
        
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

        emailManager.autofillUserScriptDidRequestUsernameAndAlias(AutofillUserScript()) { username, alias, error in
            XCTAssertNil(error)
            XCTAssertEqual(username, "username")
            XCTAssertEqual(alias, "testAlias2")
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }

    }

    func testWhenGettingWaitListStateAndWaitlistHasNoTokenOrInviteCodeThenStatusIsNotJoinedQueue() {
        let storage = MockEmailManagerStorage()
        let manager = EmailManager(storage: storage)

        XCTAssertEqual(manager.waitlistState, .notJoinedQueue)
    }

    func testWhenGettingWaitListStateAndWaitlistHasTokenAndTimestampAndNoInviteCodeThenStatusIsJoinedQueue() {
        let storage = MockEmailManagerStorage()
        storage.store(waitlistToken: "Token")
        storage.store(waitlistTimestamp: 42)
        let manager = EmailManager(storage: storage)

        XCTAssertEqual(manager.waitlistState, .joinedQueue)
    }

    func testWhenGettingWaitListStateAndWaitlistHasInviteCodeThenStatusIsJoinedQueue() {
        let storage = MockEmailManagerStorage()
        storage.store(waitlistToken: "Token")
        storage.store(waitlistTimestamp: 42)
        storage.store(inviteCode: "Code")
        let manager = EmailManager(storage: storage)

        XCTAssertEqual(manager.waitlistState, .inBeta)
    }

    func testWhenDeterminingWaitlistEligibilityAndStatusIsNotJoinedQueueThenUserIsEligible() {
        let storage = MockEmailManagerStorage()
        let manager = EmailManager(storage: storage)

        XCTAssertTrue(manager.eligibleToJoinWaitlist)
    }

    func testWhenDeterminingWaitlistEligibilityAndStatusIsJoinedQueueThenUserIsNotEligible() {
        let storage = MockEmailManagerStorage()
        storage.store(waitlistToken: "Token")
        storage.store(waitlistTimestamp: 42)
        let manager = EmailManager(storage: storage)

        XCTAssertFalse(manager.eligibleToJoinWaitlist)
    }

    func testWhenGettingInviteCodeAndInviteCodeIsStoredThenInviteCodeIsReturned() {
        let storage = MockEmailManagerStorage()
        storage.store(inviteCode: "Code")
        let manager = EmailManager(storage: storage)

        XCTAssertEqual(manager.inviteCode, "Code")
    }

    func testWhenGettingInviteCodeAndNoInviteCodeIsStoredThenNilIsReturned() {
        let storage = MockEmailManagerStorage()
        let manager = EmailManager(storage: storage)

        XCTAssertNil(manager.inviteCode)
    }

    func testWhenDeterminingWaitlistEligibilityAndStatusIsInBetaThenUserIsNotEligible() {
        let storage = MockEmailManagerStorage()
        storage.store(waitlistToken: "Token")
        storage.store(waitlistTimestamp: 42)
        storage.store(inviteCode: "Code")
        let manager = EmailManager(storage: storage)

        XCTAssertFalse(manager.eligibleToJoinWaitlist)
    }

    func testWhenCallingJoinWaitlistThenTokenAndTimestampAreStoredAndReturned() {
        let expectation = expectation(description: #function)
        let storage = storageForWaitlistTest(joinedWaitlist: false, hasInviteCode: false)
        let manager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        manager.requestDelegate = requestDelegate

        events.removeAll()

        let expectedEvents: [EmailManagerTestEvent] = [
            .joinWaitlistRequestMade,
            .storeWaitlistTokenCalled,
            .storeWaitlistTimestampCalled
        ]

        manager.joinWaitlist { result in
            XCTAssert(Thread.isMainThread)

            switch result {
            case .success(let response):
                XCTAssertEqual(response.token, "Token")
                XCTAssertEqual(response.timestamp, 1)
            case .failure:
                XCTFail("joinWaitlist should not fail")
            }

            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
            XCTAssertEqual(storage.getWaitlistToken(), "Token")
            XCTAssertEqual(storage.getWaitlistTimestamp(), 1)
        }
    }

    func testWhenCallingFetchInviteCodeIfNeededAndInviteCodeAlreadyExistsThenErrorIsReturned() {
        let expectation = expectation(description: #function)
        let storage = storageForWaitlistTest(joinedWaitlist: true, hasInviteCode: true)
        let manager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        manager.requestDelegate = requestDelegate

        events.removeAll()

        let expectedEvents: [EmailManagerTestEvent] = []

        manager.fetchInviteCodeIfAvailable { result in
            XCTAssert(Thread.isMainThread)

            switch result {
            case .success:
                XCTFail()
            case .failure(let error):
                XCTAssertEqual(error, .codeAlreadyExists)
            }

            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    func testWhenCallingFetchInviteCodeIfNeededAndNoWaitlistDataExistsThenErrorIsReturned() {
        let expectation = expectation(description: #function)
        let storage = storageForWaitlistTest(joinedWaitlist: false, hasInviteCode: false)
        let manager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        manager.requestDelegate = requestDelegate

        events.removeAll()

        let expectedEvents: [EmailManagerTestEvent] = []

        manager.fetchInviteCodeIfAvailable { result in
            XCTAssert(Thread.isMainThread)

            switch result {
            case .success:
                XCTFail()
            case .failure(let error):
                XCTAssertEqual(error, .notOnWaitlist)
            }

            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    func testWhenCallingFetchInviteCodeIfNeededAndInviteCodeIsNotReadyThenErrorIsReturned() {
        let expectation = expectation(description: #function)
        let storage = storageForWaitlistTest(joinedWaitlist: true, waitlistTimestamp: Int.max, hasInviteCode: false)
        let manager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.waitlistTimestamp = 1
        manager.requestDelegate = requestDelegate

        events.removeAll()

        // When the user has joined the waitlist
        // and a status call is made with a timestamp earlier than that which was stored
        // then no further calls should be made
        // and no values should be stored
        let expectedEvents: [EmailManagerTestEvent] = [
            .waitlistStatusRequestMade
        ]

        manager.fetchInviteCodeIfAvailable { result in
            XCTAssert(Thread.isMainThread)

            switch result {
            case .success:
                XCTFail()
            case .failure(let error):
                XCTAssertEqual(error, .noCodeAvailable)
            }

            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    func testWhenCallingFetchInviteCodeIfNeededAndInviteCodeIsReadyThenInviteCodeIsReturned() {
        let expectation = expectation(description: #function)
        let storage = storageForWaitlistTest(joinedWaitlist: true, waitlistTimestamp: 1, hasInviteCode: false)
        let manager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.waitlistTimestamp = 2
        manager.requestDelegate = requestDelegate

        events.removeAll()

        // When the user has joined the waitlist
        // and a status call is made with a timestamp later than that which was stored
        // then an invite code request should be made
        // and the invite code should be stored
        let expectedEvents: [EmailManagerTestEvent] = [
            .waitlistStatusRequestMade,
            .waitlistInviteCodeRequestMade,
            .storeWaitlistInviteCodeCalled
        ]

        manager.fetchInviteCodeIfAvailable { result in
            XCTAssert(Thread.isMainThread)

            switch result {
            case .success(let response):
                XCTAssertEqual(response.code, "Code")
            case .failure:
                XCTFail()
            }

            expectation.fulfill()
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

    private func storageForWaitlistTest(joinedWaitlist: Bool,
                                        waitlistTimestamp: Int = 1,
                                        hasInviteCode: Bool) -> MockEmailManagerStorage {

        let storage = MockEmailManagerStorage()

        if joinedWaitlist {
            storage.mockWaitlistToken = "Token"
            storage.mockWaitlistTimestamp = waitlistTimestamp
        }

        if hasInviteCode {
            storage.mockWaitlistInviteCode = "Code"
        }

        storage.storeWaitlistTokenCallback = { _ in
            events.append(.storeWaitlistTokenCalled)
        }

        storage.storeWaitlistTimestampCallback = { _ in
            events.append(.storeWaitlistTimestampCalled)
        }

        storage.storeWaitlistInviteCodeCallback = { _ in
            events.append(.storeWaitlistInviteCodeCalled)
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
}

class MockEmailManagerRequestDelegate: EmailManagerRequestDelegate {

    var mockAliases: [String] = []
    var waitlistTimestamp: Int = 1
    
    // swiftlint:disable function_parameter_count
    func emailManager(_ emailManager: EmailManager,
                      requested url: URL,
                      method: String,
                      headers: [String: String],
                      parameters: [String: String]?,
                      httpBody: Data?,
                      timeoutInterval: TimeInterval,
                      completion: @escaping (Data?, Error?) -> Void) {
        switch url.absoluteString {
        case EmailUrls.Url.emailAlias: processMockAliasRequest(completion)
        case EmailUrls.Url.joinWaitlist: processJoinWaitlistRequest(completion)
        case EmailUrls.Url.waitlistStatus: processWaitlistStatusRequest(completion)
        case EmailUrls.Url.getInviteCode: processWaitlistInviteCodeRequest(completion)
        default: assertionFailure("\(#file): Unsupported URL passed to mock request delegate: \(url)")
        }
    }
    // swiftlint:enable function_parameter_count

    private func processMockAliasRequest(_ completion: @escaping (Data?, Error?) -> Void) {
        events.append(.aliasRequestMade)

        if mockAliases.first != nil {
            let alias = mockAliases.removeFirst()
            let jsonString = "{\"address\":\"\(alias)\"}"
            let data = jsonString.data(using: .utf8)!
            completion(data, nil)
        } else {
            completion(nil, AliasRequestError.noDataError)
        }
    }

    private func processJoinWaitlistRequest(_ completion: @escaping (Data?, Error?) -> Void) {
        events.append(.joinWaitlistRequestMade)

        let jsonString = "{\"token\":\"Token\",\"timestamp\":1}"
        let data = jsonString.data(using: .utf8)!
        completion(data, nil)
    }

    private func processWaitlistStatusRequest(_ completion: @escaping (Data?, Error?) -> Void) {
        events.append(.waitlistStatusRequestMade)

        let jsonString = "{\"timestamp\":\(waitlistTimestamp)}"
        let data = jsonString.data(using: .utf8)!
        completion(data, nil)
    }

    private func processWaitlistInviteCodeRequest(_ completion: @escaping (Data?, Error?) -> Void) {
        events.append(.waitlistInviteCodeRequestMade)

        let jsonString = "{\"code\":\"Code\"}"
        let data = jsonString.data(using: .utf8)!
        completion(data, nil)
    }
    
}

class MockEmailManagerStorage: EmailManagerStorage {

    var mockUsername: String?
    var mockToken: String?
    var mockAlias: String?
    var mockCohort: String?
    var mockLastUseDate: String?
    var mockWaitlistToken: String?
    var mockWaitlistTimestamp: Int?
    var mockWaitlistInviteCode: String?
    var storeTokenCallback: ((String, String, String?) -> Void)?
    var storeAliasCallback: ((String) -> Void)?
    var storeLastUseDateCallback: ((String) -> Void)?
    var deleteAliasCallback: (() -> Void)?
    var deleteAuthenticationStateCallback: (() -> Void)?
    var storeWaitlistTokenCallback: ((String) -> Void)?
    var storeWaitlistTimestampCallback: ((Int) -> Void)?
    var storeWaitlistInviteCodeCallback: ((String) -> Void)?
    var deleteWaitlistStateCallback: (() -> Void)?
    
    func getUsername() -> String? {
        return mockUsername
    }
    
    func getToken() -> String? {
        return mockToken
    }
    
    func getAlias() -> String? {
        return mockAlias
    }

    func getCohort() -> String? {
        return mockCohort
    }

    func getLastUseDate() -> String? {
        return mockLastUseDate
    }

    func store(token: String, username: String, cohort: String?) {
        storeTokenCallback?(token, username, cohort)
    }
    
    func store(alias: String) {
        storeAliasCallback?(alias)
    }

    func store(lastUseDate: String) {
        storeLastUseDateCallback?(lastUseDate)
    }
    
    func deleteAlias() {
        deleteAliasCallback?()
    }
    
    func deleteAuthenticationState() {
        deleteAuthenticationStateCallback?()
    }

    func getWaitlistToken() -> String? {
        return mockWaitlistToken
    }

    func getWaitlistTimestamp() -> Int? {
        return mockWaitlistTimestamp
    }

    func getWaitlistInviteCode() -> String? {
        return mockWaitlistInviteCode
    }

    func store(waitlistToken: String) {
        mockWaitlistToken = waitlistToken
        storeWaitlistTokenCallback?(waitlistToken)
    }

    func store(waitlistTimestamp: Int) {
        mockWaitlistTimestamp = waitlistTimestamp
        storeWaitlistTimestampCallback?(waitlistTimestamp)
    }

    func store(inviteCode: String) {
        mockWaitlistInviteCode = inviteCode
        storeWaitlistInviteCodeCallback?(inviteCode)
    }

    func deleteWaitlistState() {
        deleteWaitlistStateCallback?()
    }

}
