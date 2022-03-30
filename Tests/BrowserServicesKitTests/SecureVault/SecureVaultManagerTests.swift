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
@testable import BrowserServicesKit

class SecureVaultManagerTests: XCTestCase {
    
    var mockCryptoProvider = MockCryptoProvider()
    var mockDatabaseProvider = MockDatabaseProvider()
    var mockKeystoreProvider = MockKeystoreProvider()
    
    var testVault: SecureVault!

    override func setUp() {
        super.setUp()

        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)
        mockKeystoreProvider._generatedPassword = "generated".data(using: .utf8)
        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encryptedL2Key".data(using: .utf8)

        let providers = SecureVaultProviders(crypto: mockCryptoProvider, database: mockDatabaseProvider, keystore: mockKeystoreProvider)
        self.testVault = DefaultSecureVault(authExpiry: 30, providers: providers)

    }
    
    func testWhenGettingExistingEntries_AndNoAutofillDataWasProvided_AndNoEntriesExist_ThenReturnValueIsNil() throws {
        let manager = SecureVaultManager(vault: self.testVault)
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: nil, creditCard: nil)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNil(entries.creditCard)
    }
    
    func testWhenGettingExistingEntries_AndAutofillCreditCardWasProvided_AndNoMatchingCreditCardExists_ThenReturnValueIncludesCard() throws {
        let manager = SecureVaultManager(vault: self.testVault)
        let card = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 2022)

        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: nil, creditCard: card)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNotNil(entries.creditCard)
        XCTAssertTrue(entries.creditCard!.hasAutofillEquality(comparedTo: card))
    }
    
    func testWhenGettingExistingEntries_AndAutofillCreditCardWasProvided_AndMatchingCreditCardExists_ThenReturnValueIsNil() throws {
        let card = paymentMethod(id: 1, cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 2022)
        try self.testVault.storeCreditCard(card)

        let manager = SecureVaultManager(vault: self.testVault)
        let autofillData = AutofillUserScript.DetectedAutofillData(identity: nil, credentials: nil, creditCard: card)
        let entries = try manager.existingEntries(for: "domain.com", autofillData: autofillData)
        
        XCTAssertNil(entries.credentials)
        XCTAssertNil(entries.identity)
        XCTAssertNil(entries.creditCard)
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
