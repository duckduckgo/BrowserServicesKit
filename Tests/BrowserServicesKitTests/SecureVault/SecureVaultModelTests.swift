//
//  SecureVaultModelTests.swift
//  
//
//  Created by Sam Symons on 2022-02-26.
//

import Foundation
import XCTest
@testable import BrowserServicesKit

class SecureVaultModelTests: XCTestCase {

    func testWhenIdentitiesHaveTheSameNames_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")
        
        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
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
    
    // MARK: - Test Utilities
    
    private func identity(named name: (String, String, String), addressStreet: String) -> SecureVaultModels.Identity {
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
                                          addressStreet: nil,
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
