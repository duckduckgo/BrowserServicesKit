//
//  AutofillEmailUserScriptTests.swift
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
import WebKit
@testable import BrowserServicesKit

class AutofillEmailUserScriptTests: XCTestCase {

    let userScript = AutofillUserScript()
    let userContentController = WKUserContentController()

    func testWhenReceivesStoreTokenMessageThenCallsDelegateMethodWithCorrectTokenAndUsername() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock
        
        let token = "testToken"
        let username = "testUsername"
                
        let expect = expectation(description: "testWhenReceivesStoreTokenMessageThenCallsDelegateMethod")
        mock.requestStoreTokenCallback = { callbackToken, callbackUsername in
            XCTAssertEqual(token, callbackToken)
            XCTAssertEqual(username, callbackUsername)
            expect.fulfill()
        }
        
        let message = MockWKScriptMessage(name: "emailHandlerStoreToken", body: [ "token": "testToken", "username": "testUsername"])
        userScript.userContentController(userContentController, didReceive: message)

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testWhenReceivesCheckSignedInMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let expect = expectation(description: "testWhenReceivesCheckSignedInMessageThenCallsDelegateMethod")
        mock.signedInCallback = {
            expect.fulfill()
        }

        let message = MockWKScriptMessage(name: "emailHandlerCheckAppSignedInStatus", body: "")
        userScript.userContentController(userContentController, didReceive: message)

        waitForExpectations(timeout: 1.0, handler: nil)
    }
   
    func testWhenReceivesGetAliasMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock
        
        let expect = expectation(description: "testWhenReceivesGetAliasMessageThenCallsDelegateMethod")
        mock.requestAliasCallback = {
            expect.fulfill()
        }
        
        let message = MockWKScriptMessage(name: "emailHandlerGetAlias",
                                          body: ["requiresUserPermission": false, "shouldConsumeAliasIfProvided": false])
        userScript.userContentController(userContentController, didReceive: message)

        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    func testWhenReceivesRefreshAliasMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock
        
        let expect = expectation(description: "testWhenReceivesRefreshAliasMessageThenCallsDelegateMethod")
        mock.refreshAliasCallback = {
            expect.fulfill()
        }
        
        let message = MockWKScriptMessage(name: "emailHandlerRefreshAlias", body: "")
        userScript.userContentController(userContentController, didReceive: message)

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testWhenReceivesRequestUsernameAndAliasMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let expect = expectation(description: "testWhenReceivesRequestUsernameAndAliasMessageThenCallsDelegateMethod")
        mock.requestUsernameAndAliasCallback = {
            expect.fulfill()
        }

        let message = MockWKScriptMessage(name: "emailHandlerGetAddresses", body: "")
        userScript.userContentController(userContentController, didReceive: message)

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testWhenUnknownMessageReceivedThenNoProblem() {
        let message = MockWKScriptMessage(name: "unknownmessage", body: "")
        userScript.userContentController(userContentController, didReceive: message)
    }

}

class MockWKScriptMessage: WKScriptMessage {
    
    let mockedName: String
    let mockedBody: Any
    
    override var name: String {
        return mockedName
    }
    
    override var body: Any {
        return mockedBody
    }
    
    init(name: String, body: Any) {
        self.mockedName = name
        self.mockedBody = body
        super.init()
    }
}

class MockAutofillEmailDelegate: AutofillEmailDelegate {

    var signedInCallback: (() -> Void)?
    var requestAliasCallback: (() -> Void)?
    var requestStoreTokenCallback: ((String, String) -> Void)?
    var refreshAliasCallback: (() -> Void)?
    var requestUsernameAndAliasCallback: (() -> Void)?

    func autofillUserScriptDidRequestSignedInStatus(emailUserScript: AutofillUserScript) -> Bool {
        signedInCallback!()
        return false
    }
    
    func autofillUserScript(_: AutofillUserScript,
                            didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                            shouldConsumeAliasIfProvided: Bool,
                            completionHandler: @escaping AliasCompletion) {
        requestAliasCallback!()
    }
    
    func autofillUserScriptDidRequestRefreshAlias(_ : AutofillUserScript) {
        refreshAliasCallback!()
    }
    
    func autofillUserScript(_ : AutofillUserScript, didRequestStoreToken token: String, username: String) {
        requestStoreTokenCallback!(token, username)
    }

    func autofillUserScriptDidRequestUsernameAndAlias(_: AutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion) {
        requestUsernameAndAliasCallback!()
    }

}
