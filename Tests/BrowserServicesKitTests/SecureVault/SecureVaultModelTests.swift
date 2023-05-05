//
//  SecureVaultModelsTests.swift
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

import Foundation
import XCTest
import Common
@testable import BrowserServicesKit

class SecureVaultModelsTests: XCTestCase {

    var tld = TLD()

    private func testAccount(_ username: String, _ domain: String, _ signature: String, _ lastUpdated: Double) -> SecureVaultModels.WebsiteAccount {
        return SecureVaultModels.WebsiteAccount(id: "1234567890",
                                                username: username,
                                                domain: domain,
                                                signature: signature,
                                                created: Date(timeIntervalSince1970: 0),
                                                lastUpdated: Date(timeIntervalSince1970: lastUpdated))

    }


    func testExactMatchIsReturnedWhenDuplicates() {
        // Test the exact match is returned when duplicates
        let accounts = [
            testAccount("daniel", "amazon.com", "12345", 0),
            testAccount("daniel", "www.amazon.com", "12345", 0),
            testAccount("daniel", "aws.amazon.com", "12345", 0),
            testAccount("daniel", "login.amazon.com", "12345", 10)
        ]
            .removingDuplicatesForDomain("amazon.com", tld: tld)
        XCTAssertEqual(accounts.first, testAccount("daniel", "amazon.com", "12345", 0))
    }

    func testTLDAccountIsReturnedWhenDuplicates() {
        // Test the account with the TLD is returned when duplicates
        let accounts = [
            testAccount("mary", "www.amazon.com", "0987", 0),
            testAccount("mary", "aws.amazon.com", "0987", 1),
            testAccount("mary", "amazon.com", "0987", 1)
        ]
            .removingDuplicatesForDomain("signin.amazon.com", tld: tld)
        XCTAssertEqual(accounts.first, testAccount("mary", "amazon.com", "0987", 1))
    }

    func testLastEditedAccountIsReturnedIfNoExactMatches() {
        // Test the last edited account is returned if no exact match/or TLD account
        let accounts = [
            testAccount("daniel", "www.amazon.com", "12345", 0),
            testAccount("daniel", "aws.amazon.com", "12345", 0),
            testAccount("daniel", "signup.amazon.com", "12345", 10)
        ]
            .removingDuplicatesForDomain("amazon.com", tld: tld)
        XCTAssertEqual(accounts.first, testAccount("daniel", "signup.amazon.com", "12345", 10) )
    }

    func testNonDuplicateAccountsAreReturned() {
        // Test non duplicate accounts are also returned
        let accounts = [
            testAccount("daniel", "www.amazon.com", "12345", 0),
            testAccount("daniel", "www.amazon.com", "12345", 0),
            testAccount("daniel", "www.amazon.com", "12345", 10),
            testAccount("daniel", "aws.amazon.com", "7890", 0),
        ]
            .removingDuplicatesForDomain("amazon.com", tld: tld)
        XCTAssertTrue(accounts.contains(where: { $0 == testAccount("daniel", "www.amazon.com", "12345", 10) }))
        XCTAssertTrue(accounts.contains(where: { $0 ==  testAccount("daniel", "aws.amazon.com", "7890", 0) }))
    }

    func testMultipleDuplicatesAreFilteredAndNonDuplicatesReturned() {
        // Test multiple duplicates are filtered correctly, and non-duplicates are returned
        let accounts = [
            testAccount("daniel", "amazon.com", "12345", 0),
            testAccount("daniel", "www.amazon.com", "12345", 0),
            testAccount("daniel", "login.amazon.com", "12345", 0),
            testAccount("jane", "aws.amazon.com", "7111", 0),
            testAccount("jane", "login.amazon.com", "7111", 0),
            testAccount("jane", "amazon.com", "7111", 0),
            testAccount("mary", "www.amazon.com", "0987", 0),
            testAccount("mary", "aws.amazon.com", "0987", 1),
        ]
            .removingDuplicatesForDomain("www.amazon.com", tld: tld)
        XCTAssertTrue(accounts.contains(where: { $0 ==  testAccount("daniel", "www.amazon.com", "12345", 0) }))
        XCTAssertTrue(accounts.contains(where: { $0 == testAccount("jane", "amazon.com", "7111", 0) }))
        XCTAssertTrue(accounts.contains(where: { $0 == testAccount("mary", "www.amazon.com", "0987", 0) }))

    }

    func testSortingWorksAsExpected() {
        let accounts = [
            testAccount("mary", "www.amazon.com", "0987", 100),
            testAccount("daniel", "www.amazon.com", "12345", 0),
            testAccount("john", "www.amazon.com", "12345", 0),
            testAccount("", "www.amazon.com", "12345", 0),
            testAccount("daniel", "amazon.com", "12345", 100),
            testAccount("jane", "amazon.com", "7111", 25),
            testAccount("", "amazon.com", "7111", 0),
            testAccount("mary", "aws.amazon.com", "0987", 10),
            testAccount("jane", "aws.amazon.com", "7111", 0),
            testAccount("adam", "login.amazon.com", "7111", 50),
            testAccount("jane", "login.amazon.com", "7111", 50),
            testAccount("joe", "login.amazon.com", "7111", 50),
            testAccount("daniel", "login.amazon.com", "12345", 0),
            testAccount("daniel", "xyz.amazon.com", "12345", 0)
        ]
            .sortedForDomain("www.amazon.com", tld: tld)
        XCTAssertEqual(accounts[0], testAccount("mary", "www.amazon.com", "0987", 100))
        XCTAssertEqual(accounts[1],  testAccount("daniel", "www.amazon.com", "12345", 0))
        XCTAssertEqual(accounts[2], testAccount("john", "www.amazon.com", "12345", 0))
        XCTAssertEqual(accounts[3], testAccount("", "www.amazon.com", "12345", 0))
        XCTAssertEqual(accounts[4], testAccount("daniel", "amazon.com", "12345", 100))
        XCTAssertEqual(accounts[5], testAccount("jane", "amazon.com", "7111", 25))
        XCTAssertEqual(accounts[6], testAccount("", "amazon.com", "7111", 0))
        XCTAssertEqual(accounts[7], testAccount("adam", "login.amazon.com", "7111", 50))
        XCTAssertEqual(accounts[8], testAccount("jane", "login.amazon.com", "7111", 50))
        XCTAssertEqual(accounts[9], testAccount("joe", "login.amazon.com", "7111", 50))
        XCTAssertEqual(accounts[10], testAccount("mary", "aws.amazon.com", "0987", 10))
        XCTAssertEqual(accounts[11], testAccount("jane", "aws.amazon.com", "7111", 0))
        XCTAssertEqual(accounts[12], testAccount("daniel", "login.amazon.com", "12345", 0))
        XCTAssertEqual(accounts[13], testAccount("daniel", "xyz.amazon.com", "12345", 0))





    }
    


}
