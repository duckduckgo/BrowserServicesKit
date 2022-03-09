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
//

import Foundation
import XCTest
@testable import BrowserServicesKit

class SecureVaultModelTests: XCTestCase {
    
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

}
