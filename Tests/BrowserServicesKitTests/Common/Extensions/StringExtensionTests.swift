//
//  StringExtensionTests.swift
//  
//
//  Created by Sam Symons on 2022-02-26.
//

import Foundation

import XCTest
@testable import BrowserServicesKit

final class StringExtensionTests: XCTestCase {

    func testWhenNormalizingStringsForAutofill_ThenDiacriticsAreRemoved() {
        let stringToNormalize = "Dáx Thê Dûck"
        let normalizedString = stringToNormalize.autofillNormalized()
        
        XCTAssertEqual(normalizedString, "daxtheduck")
    }
    
    func testWhenNormalizingStringsForAutofill_ThenWhitespaceIsRemoved() {
        let stringToNormalize = "Dax The Duck"
        let normalizedString = stringToNormalize.autofillNormalized()
        
        XCTAssertEqual(normalizedString, "daxtheduck")
    }
    
    func testWhenNormalizingStringsForAutofill_ThenPunctuationIsRemoved() {
        let stringToNormalize = ",Dax+The_Duck."
        let normalizedString = stringToNormalize.autofillNormalized()
        
        XCTAssertEqual(normalizedString, "daxtheduck")
    }
    
    func testWhenNormalizingStringsForAutofill_ThenNumbersAreRetained() {
        let stringToNormalize = "Dax123"
        let normalizedString = stringToNormalize.autofillNormalized()
        
        XCTAssertEqual(normalizedString, "dax123")
    }
    
    func testWhenNormalizingStringsForAutofill_ThenStringsThatDoNotNeedNormalizationAreUntouched() {
        let stringToNormalize = "firstmiddlelast"
        let normalizedString = stringToNormalize.autofillNormalized()
        
        XCTAssertEqual(normalizedString, "firstmiddlelast")
    }
    
    func testWhenNormalizingStringsForAutofill_ThenEmojiAreRemoved() {
        let stringToNormalize = "Dax 🤔"
        let normalizedString = stringToNormalize.autofillNormalized()
        
        XCTAssertEqual(normalizedString, "dax")
    }

}
