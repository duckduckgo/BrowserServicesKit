//
//  VaultUserScriptTests.swift
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
@testable import SecureVault
import WebKit

class VaultUserScriptTests: XCTestCase {

    let script = VaultUserScript(domainProvider: MockDomainProvider(domain: "example.com"))
    let userContentController = WKUserContentController()
    let mockDelegate = MockDelegate()

    override func setUp() {
        script.delegate = mockDelegate
    }

    func testWhenRequestingStorageOfCredentials_ThenDelegateIsCalledWithCredentials() {
        let message = MockWKScriptMessage(name: VaultUserScript.MessageNames.vaultStoreCredentials.rawValue, body: [
            VaultUserScript.MessageNames.StoreCredentialsArgNames.username.rawValue: "username",
            VaultUserScript.MessageNames.StoreCredentialsArgNames.password.rawValue: "password"
        ])
        script.userContentController(userContentController, didReceive: message)
        XCTAssertEqual("example.com", mockDelegate.credentials?.account.domain)
        XCTAssertEqual("password".data(using: .utf8), mockDelegate.credentials?.password)
        XCTAssertEqual("username", mockDelegate.credentials?.account.username)
    }

    func testWhenRequestingAccounts_ThenDelegateIsCalledWithDomain() {
        let message = MockWKScriptMessage(name: VaultUserScript.MessageNames.vaultRequestAccounts.rawValue, body: [:])
        script.userContentController(userContentController, didReceive: message)
        XCTAssertEqual("example.com", mockDelegate.domain)
    }

    func testWhenRequestingCredentialsMessageReceived_ThenDelegateIsCalledWithDomain() {
        let message = MockWKScriptMessage(name: VaultUserScript.MessageNames.vaultRequestCredentials.rawValue, body: [
            VaultUserScript.MessageNames.RequestCredentialsArgNames.id.rawValue: 23
        ])
        script.userContentController(userContentController, didReceive: message)
        XCTAssertEqual(23, mockDelegate.id)
    }

    func testWhenUserScriptCreated_ThenSourceIsLoaded() {
        XCTAssertNotNil(script.source)
    }

    class MockDelegate: NSObject, VaultUserScriptDelegate {

        var credentials: SecureVaultModels.WebsiteCredentials?
        var id: Int64?
        var domain: String?

        func vaultUserScript(_ userScript: VaultUserScript, requestingStoreCredentials credentials: SecureVaultModels.WebsiteCredentials) {
            self.credentials = credentials
        }

        func vaultUserScript(_ userScript: VaultUserScript, requestingCredentialsForId id: Int64) {
            self.id = id
        }

        func vaultUserScript(_ userScript: VaultUserScript, requestingAccountsForDomain domain: String) {
            self.domain = domain
        }
    }

    struct MockDomainProvider: DomainProviding {
        let domain: String
        func domainFrom(message: WKScriptMessage) -> String? {
            return domain
        }
    }
}
