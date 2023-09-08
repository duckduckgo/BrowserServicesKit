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

    // swiftlint:disable:next large_tuple
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
    private var days = 86400.0

    private func testAccount(_ username: String, _ domain: String, _ signature: String, _ lastUpdated: Double) -> SecureVaultModels.WebsiteAccount {
        return SecureVaultModels.WebsiteAccount(id: "1234567890",
                                                username: username,
                                                domain: domain,
                                                signature: signature,
                                                created: Date(timeIntervalSince1970: 0),
                                                lastUpdated: Date(timeIntervalSince1970: lastUpdated))

    }

    lazy var sortTestAccounts = [
        testAccount("", "appliances.amazon.com", "5678", 0),
        testAccount("mary", "garden.amazon.com", "12345", 50 * days),
        testAccount("daniel", "www.amazon.com", "23456", 0),
        testAccount("lisa", "books.amazon.com", "5678", 50  * days),
        testAccount("peter", "primevideo.amazon.com", "4567", 85 * days),
        testAccount("jane", "amazon.com", "7890", 0),
        testAccount("", "", "7890", 0),
        testAccount("", "amazon.com", "3456", 0),
        testAccount("william", "fashion.amazon.com", "1234", 50 * days),
        testAccount("olivia", "toys.amazon.com", "4567", 50 * days),
        testAccount("", "movies.amazon.com", "2345", 0),
        testAccount("jacob", "office.amazon.com", "12345", 0),
        testAccount("rachel", "amazon.com", "7890", 0),
        testAccount("james", "", "7890", 0),
        testAccount("", "grocery.amazon.com", "4567", 0),
        testAccount("frank", "sports.amazon.com", "23456", 0),
        testAccount("quinn", "www.amazon.com", "2345", 0),
        testAccount("oscar", "amazon.com", "7890", 0),
        testAccount("chris", "baby.amazon.com", "3456", 0),
        testAccount("anna", "amazon.com", "1234", 50 * days),
        testAccount("paul", "amazon.com", "3456", 0),
        testAccount("john", "www.amazon.com", "4567", 0)
    ]

    func testExactMatchAccountsAreShownFirst() {
        let sortedAccounts = sortTestAccounts.sortedForDomain("www.amazon.com", tld: tld)

        let controlAccounts = [
            testAccount("daniel", "www.amazon.com", "23456", 0),
            testAccount("john", "www.amazon.com", "4567", 0),
            testAccount("quinn", "www.amazon.com", "2345", 0),
            testAccount("anna", "amazon.com", "1234", 50 * days),
            testAccount("jane", "amazon.com", "7890", 0),
            testAccount("oscar", "amazon.com", "7890", 0),
            testAccount("paul", "amazon.com", "3456", 0),
            testAccount("rachel", "amazon.com", "7890", 0),
            testAccount("", "amazon.com", "3456", 0),
            testAccount("peter", "primevideo.amazon.com", "4567", 85 * days),
            testAccount("lisa", "books.amazon.com", "5678", 50 * days),
            testAccount("william", "fashion.amazon.com", "1234", 50 * days),
            testAccount("mary", "garden.amazon.com", "12345", 50 * days),
            testAccount("olivia", "toys.amazon.com", "4567", 50 * days),
            testAccount("chris", "baby.amazon.com", "3456", 0),
            testAccount("jacob", "office.amazon.com", "12345", 0),
            testAccount("frank", "sports.amazon.com", "23456", 0),
            testAccount("", "appliances.amazon.com", "5678", 0),
            testAccount("", "grocery.amazon.com", "4567", 0),
            testAccount("", "movies.amazon.com", "2345", 0)
        ]
        for i in 0...18 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testWWWAccountsAreConsideredTopLevel() {

        let sortedAccounts = sortTestAccounts.sortedForDomain("amazon.com", tld: tld)
        let controlAccounts = [
            testAccount("anna", "amazon.com", "1234", 50 * days),
            testAccount("jane", "amazon.com", "7890", 0),
            testAccount("oscar", "amazon.com", "7890", 0),
            testAccount("paul", "amazon.com", "3456", 0),
            testAccount("rachel", "amazon.com", "7890", 0),
            testAccount("", "amazon.com", "3456", 0),
            testAccount("daniel", "www.amazon.com", "23456", 0),
            testAccount("john", "www.amazon.com", "4567", 0),
            testAccount("quinn", "www.amazon.com", "2345", 0),
        ]
        for i in 0...8 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testExactSubdomainMatchIsFirstFollowedByTLDAndWWW() {

        let sortedAccounts  = sortTestAccounts.sortedForDomain("toys.amazon.com", tld: tld)
        let controlAccounts  = [
            testAccount("olivia", "toys.amazon.com", "4567", 50 * days),
            testAccount("anna", "amazon.com", "1234", 50 * days),
            testAccount("jane", "amazon.com", "7890", 0),
            testAccount("oscar", "amazon.com", "7890", 0),
            testAccount("paul", "amazon.com", "3456", 0),
            testAccount("rachel", "amazon.com", "7890", 0),
            testAccount("daniel", "www.amazon.com", "23456", 0),
            testAccount("john", "www.amazon.com", "4567", 0),
            testAccount("quinn", "www.amazon.com", "2345", 0),
            testAccount("", "amazon.com", "3456", 0),
            testAccount("peter", "primevideo.amazon.com", "4567", 85 * days),
            testAccount("lisa", "books.amazon.com", "5678", 50 * days),
            testAccount("william", "fashion.amazon.com", "1234", 50 * days),
            testAccount("mary", "garden.amazon.com", "12345", 50 * days),
            testAccount("chris", "baby.amazon.com", "3456", 0),
            testAccount("jacob", "office.amazon.com", "12345", 0),
            testAccount("frank", "sports.amazon.com", "23456", 0),
            testAccount("", "appliances.amazon.com", "5678", 0),
            testAccount("", "grocery.amazon.com", "4567", 0),
            testAccount("", "movies.amazon.com", "2345", 0)
        ]
        XCTAssertTrue(sortedAccounts.count == controlAccounts.count)
        for i in 0...19 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testDuplicatesAreProperlyRemoved() {
        // (Note Duplicates are removed exclusively based on signature -- Ignoring usernames/domains)
        let sortedAccounts  = sortTestAccounts.sortedForDomain("toys.amazon.com", tld: tld, removeDuplicates: true)
        let controlAccounts  = [
            testAccount("olivia", "toys.amazon.com", "4567", 50 * days),
            testAccount("anna", "amazon.com", "1234", 50 * days),
            testAccount("jane", "amazon.com", "7890", 0),
            testAccount("paul", "amazon.com", "3456", 0),
            testAccount("daniel", "www.amazon.com", "23456", 0),
            testAccount("quinn", "www.amazon.com", "2345", 0),
            testAccount("lisa", "books.amazon.com", "5678", 50 * days),
            testAccount("mary", "garden.amazon.com", "12345", 50 * days),
        ]
        for i in 0...7 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testPatternMatchedTitle() {
        
        let domainTitles: [String] = [
            "duck.com",
            "duck.com (test@duck.com)",
            "https://duck.com",
            "https://duck.com (test@duck.com)",
            "https://duck.com?page.php?test=variable1&b=variable2",
            "https://duck.com/section/page.php?test=variable1&b=variable2",
            "www.duck.com",
            "www.duck.com (test@duck.com)",
            "https://www.duck.com",
            "https://www.duck.com (test@duck.com)",
            "https://www.duck.com?page.php?test=variable1&b=variable2",
            "https://www.duck.com/section/page.php?test=variable1&b=variable2",
            "https://WwW.dUck.com/section/page"
        ]
        
        let subdomainTitles: [String] = [
            "signin.duck.com",
            "signin.duck.com (test@duck.com.co)",
            "https://signin.duck.com",
            "https://signin.duck.com (test@duck.com.co)",
            "https://signin.duck.com?page.php?test=variable1&b=variable2",
            "https://signin.duck.com/section/page.php?test=variable1&b=variable2",
            "https://SiGnIn.dUck.com/section/page"
        ]
        
        let tldPlusOneTitles: [String] = [
            "signin.duck.com.co",
            "signin.duck.com.co (test@duck.com.co)",
            "https://signin.duck.com.co",
            "https://signin.duck.com.co (test@duck.com.co)",
            "https://signin.duck.com.co?page.php?test=variable1&b=variable2",
            "https://signin.duck.com.co/section/page.php?test=variable1&b=variable2",
            "https://SiGnIn.dUck.com.CO/section/page"
        ]
                        
        for title in domainTitles {
            let account = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "sometestdomain.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("duck.com", account.patternMatchedTitle(), "Failed for title: \(title)")
            
            let equalDomain = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "duck.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("", equalDomain.patternMatchedTitle(), "Failed for title: \(title)")
        }
        
        for title in subdomainTitles {
            let account = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "sometestdomain.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("signin.duck.com", account.patternMatchedTitle(), "Failed for title: \(title)")
            
            let equalDomain = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "signin.duck.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("", equalDomain.patternMatchedTitle(), "Failed for title: \(title)")
        }
        
        for title in tldPlusOneTitles {
            let account = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "sometestdomain.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("signin.duck.com.co", account.patternMatchedTitle(), "Failed for title: \(title)")
            
            let equalDomain = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "signin.duck.com.co", created: Date(), lastUpdated: Date())
            XCTAssertEqual("", equalDomain.patternMatchedTitle(), "Failed for title: \(title)")
        }
        
    }
    
    
}
