//
//  SecureVaultModelTests.swift
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

import Foundation
import XCTest
import Common
@testable import BrowserServicesKit

class SecureVaultModelTests: XCTestCase {

    // MARK: - Identities

    func testWhenCreatingIdentities_ThenTheyHaveCachedAutofillProperties() {
        let identity = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertEqual(identity.autofillEqualityName, "firstmiddlelast")
        XCTAssertEqual(identity.autofillEqualityAddressStreet, "addressstreet")
    }


    func testWhenCreatingIdentities_AndTheyHaveCachedAutofillProperties_ThenMutatingThePropertiesUpdatesTheCachedVersions() {
        var identity = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertEqual(identity.autofillEqualityName, "firstmiddlelast")
        XCTAssertEqual(identity.autofillEqualityAddressStreet, "addressstreet")

        identity.firstName = "Dax"
        identity.middleName = "The"
        identity.lastName = "Duck"
        identity.addressStreet = "New Street"

        XCTAssertEqual(identity.autofillEqualityName, "daxtheduck")
        XCTAssertEqual(identity.autofillEqualityAddressStreet, "newstreet")
    }

    func testWhenIdentitiesHaveTheSameNames_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndNoAddress_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First", "Middle", "Last"), addressStreet: nil)
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: nil)

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndDifferentAddresses_ThenAutoFillEqualityIsFalse() {
        let identity1 = identity(named: ("First", "Middle", "Last"), addressStreet: "First Address")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Second Address")

        XCTAssertFalse(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndHaveArbitraryWhitespace_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First ", " Middle", " Last"), addressStreet: " Address Street ")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndSomeNamesHaveDiacritics_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("Fírst", "Mïddlé", "Lâst"), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndSomeNamesHaveEmoji_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First 😎", "Middle", "Last"), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheFullNameInOneField_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First Middle Last", "", ""), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveDifferentNames_ButOtherValuesMatch_ThenAutofillEqualityIsFalse() {
        let identity1 = identity(named: ("One", "Two", "Three"), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertFalse(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testIdentityEqualityPerformance() {
        let identity = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        let identitiesToCheck = (1...10000).map {
            return self.identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street \($0)")
        }

        measure {
            for identityToCheck in identitiesToCheck {
                _ = identity.hasAutofillEquality(comparedTo: identityToCheck)
            }
        }
    }

    // MARK: - Payment Methods

    func testWhenCardNumbersAreTheSame_ThenAutofillEqualityIsTrue() {
        let card1 = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)
        let card2 = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)

        XCTAssertTrue(card1.hasAutofillEquality(comparedTo: card2))
    }

    func testWhenCardNumbersAreTheSame_ButTheyHaveDifferentSpacing_ThenAutofillEqualityIsTrue() {
        let card1 = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)
        let card2 = paymentMethod(cardNumber: "5555 5555 5555 5557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)

        XCTAssertTrue(card1.hasAutofillEquality(comparedTo: card2))
    }

    func testWhenCardNumbersAreDifferent_ThenAutofillEqualityIsFalse() {
        let card1 = paymentMethod(cardNumber: "1234 1234 1234 1234", cardholderName: "Name", cvv: "123", month: 1, year: 3000)
        let card2 = paymentMethod(cardNumber: "5555 5555 5555 5557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)

        XCTAssertFalse(card1.hasAutofillEquality(comparedTo: card2))
    }

    func testPaymentMethodEqualityPerformance() {
        let paymentMethod = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)

        let cardsToCheck = (1...10000).map {
            return self.paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name \($0)", cvv: "123", month: 1, year: 3000)
        }

        measure {
            for cardToCheck in cardsToCheck {
                _ = paymentMethod.hasAutofillEquality(comparedTo: cardToCheck)
            }
        }
    }

    // MARK: - Test Utilities

    private func identity(named name: (String, String, String), addressStreet: String?) -> SecureVaultModels.Identity {
        return SecureVaultModels.Identity(id: nil,
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

    private func paymentMethod(cardNumber: String,
                               cardholderName: String,
                               cvv: String,
                               month: Int,
                               year: Int) -> SecureVaultModels.CreditCard {
        return SecureVaultModels.CreditCard(id: nil,
                                            title: nil,
                                            cardNumber: cardNumber,
                                            cardholderName: cardholderName,
                                            cardSecurityCode: cvv,
                                            expirationMonth: month,
                                            expirationYear: year)
    }

    // MARK: WebsiteAccounts

    private var tld = TLD()

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
            .removingDuplicatesForDomain("www.amazon.com", tld: tld)
        XCTAssertEqual(accounts.first,  testAccount("daniel", "www.amazon.com", "12345", 0))
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
