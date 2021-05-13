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

enum AliasFetchingTestEvent {
    case getAliasCallbackCalled
    case deleteAliasCalled
    case storeAliasCalled
    case storeTokenCalled
    case requestMade
}

var events = [AliasFetchingTestEvent]()

class EmailManagerTests: XCTestCase {

    func testWhenSignOutThenDeletesAllStorage() {
        
        let storage = MockEmailManagerStorage()
        let emailManager = EmailManager(storage: storage)
        
        let expect = expectation(description: "testWhenReceivesStoreTokenMessageThenCallsDelegateMethod")
        storage.deleteAllCallback = {
            expect.fulfill()
        }
        
        emailManager.signOut()
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testWhenCallingGetAliasWithAliasStoredThenAliasReturnedAndNewAliasFetched() {
        
        let expect = expectation(description: "testWhenCallingGetAliasWithAliasStoredThenAliasReturnedAndNewAliasFetched")
        let storage = storageForGetAliasTest(signedIn: true, storedAlias: true, fulfullOnFirstStorageEvent: true, expectationToFulfill: expect)
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
        let expectedEvents: [AliasFetchingTestEvent] = [
            .getAliasCallbackCalled,
            .deleteAliasCalled,
            .requestMade,
            .storeAliasCalled
        ]
                
        emailManager.getAliasEmailIfNeededAndConsume { alias, _ in
            XCTAssertEqual(alias, "testAlias1@duck.com")
            events.append(.getAliasCallbackCalled)
        }
        
        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }
    
    func testWhenCallingGetAliasWithNoAliasStoredThenAliasFetchedAndNewAliasFetched() {
        
        let expect = expectation(description: "testWhenCallingGetAliasWithNoAliasStoredThenAliasFetchedAndNewAliasFetched")
        let storage = storageForGetAliasTest(signedIn: true, storedAlias: false, fulfullOnFirstStorageEvent: false, expectationToFulfill: expect)
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
        
        let expectedEvents: [AliasFetchingTestEvent] = [
            .requestMade,
            .storeAliasCalled,
            .getAliasCallbackCalled,
            .deleteAliasCalled,
            .requestMade,
            .storeAliasCalled
        ]
        
        emailManager.getAliasEmailIfNeededAndConsume { alias, _ in
            XCTAssertEqual(alias, "testAlias2@duck.com")
            events.append(.getAliasCallbackCalled)
        }
        
        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }
    
    func testWhenCallingGetAliasWhenSignedOutThenNoAliasReturned() {
        let expect = expectation(description: "testWhenCallingGetAliasWhenSignedOutThenNoAliasReturned")
        let storage = storageForGetAliasTest(signedIn: false, storedAlias: false, fulfullOnFirstStorageEvent: false, expectationToFulfill: expect)
        let emailManager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.mockAliases = ["testAlias2", "testAlias3"]
        emailManager.requestDelegate = requestDelegate
                
        events.removeAll()

        let expectedEvents: [AliasFetchingTestEvent] = [
            .getAliasCallbackCalled
        ]
        
        emailManager.getAliasEmailIfNeededAndConsume { alias, error in
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
        let expect = expectation(description: "testWhenStoreTokenThenRequestForAliasMade")
        let storage = storageForGetAliasTest(signedIn: true, storedAlias: false, fulfullOnFirstStorageEvent: true, expectationToFulfill: expect)
        let emailManager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.mockAliases = ["testAlias2", "testAlias3"]
        emailManager.requestDelegate = requestDelegate
        
        events.removeAll()
        
        let expectedEvents: [AliasFetchingTestEvent] = [
            .storeTokenCalled,
            .requestMade,
            .storeAliasCalled
        ]
        
        emailManager.autofillUserScript(AutofillUserScript(), didRequestStoreToken: "token", username: "username")
        
        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }
    }

    func testWhenRequestingUsernameAndAliasThenTheyAreReturned() {

        let expect = expectation(description: "testWhenRequestingUsernameAndAliasThenTheyAreReturned")
        let storage = storageForGetAliasTest(signedIn: true, storedAlias: false, fulfullOnFirstStorageEvent: true, expectationToFulfill: expect)
        let emailManager = EmailManager(storage: storage)
        let requestDelegate = MockEmailManagerRequestDelegate()
        requestDelegate.mockAliases = ["testAlias2", "testAlias3"]
        emailManager.requestDelegate = requestDelegate

        events.removeAll()

        let expectedEvents: [AliasFetchingTestEvent] = [
            .requestMade,
            .storeAliasCalled
        ]

        emailManager.autofillUserScriptDidRequestUsernameAndAlias(AutofillUserScript()) { username, alias, error in
            XCTAssertNil(error)
            XCTAssertEqual(username, "username")
            XCTAssertEqual(alias, "testAlias2@duck.com")
        }

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(events, expectedEvents)
        }

    }

    private func storageForGetAliasTest(signedIn: Bool,
                                        storedAlias: Bool,
                                        fulfullOnFirstStorageEvent: Bool,
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
        
        storage.storeTokenCallback = { _, _ in
            events.append(.storeTokenCalled)
        }
                        
        var isFirstStorage = true
        storage.storeAliasCallback = { alias in
            events.append(.storeAliasCalled)
            if isFirstStorage {
                XCTAssertEqual(alias, "testAlias2")
                isFirstStorage = false
                if fulfullOnFirstStorageEvent {
                    expectationToFulfill.fulfill()
                }
            } else {
                XCTAssertEqual(alias, "testAlias3")
                expectationToFulfill.fulfill()
            }
        }

        return storage
    }
}

class MockEmailManagerRequestDelegate: EmailManagerRequestDelegate {
    
    var mockAliases: [String] = []
    
    // swiftlint:disable function_parameter_count
    func emailManager(_ emailManager: EmailManager,
                      didRequestAliasWithURL url: URL,
                      method: String, headers: [String: String],
                      timeoutInterval: TimeInterval,
                      completion: @escaping (Data?, Error?) -> Void) {
        events.append(.requestMade)
        if mockAliases.first != nil {
            let alias = mockAliases.removeFirst()
            let jsonString = "{\"address\":\"\(alias)\"}"
            let data = jsonString.data(using: .utf8)!
            completion(data, nil)
        } else {
            completion(nil, AliasRequestError.noDataError)
        }
    }
    // swiftlint:enable function_parameter_count
    
}

class MockEmailManagerStorage: EmailManagerStorage {
    
    var mockUsername: String?
    var mockToken: String?
    var mockAlias: String?
    var storeTokenCallback: ((String, String) -> Void)?
    var storeAliasCallback: ((String) -> Void)?
    var deleteAliasCallback: (() -> Void)?
    var deleteAllCallback: (() -> Void)?
    
    func getUsername() -> String? {
        return mockUsername
    }
    
    func getToken() -> String? {
        return mockToken
    }
    
    func getAlias() -> String? {
        return mockAlias
    }
    
    func store(token: String, username: String) {
        storeTokenCallback?(token, username)
    }
    
    func store(alias: String) {
        storeAliasCallback?(alias)
    }
    
    func deleteAlias() {
        deleteAliasCallback?()
    }
    
    func deleteAll() {
        deleteAllCallback?()
    }
}
