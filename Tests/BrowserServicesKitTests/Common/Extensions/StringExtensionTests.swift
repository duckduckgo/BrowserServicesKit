//
//  StringExtensionTests.swift
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
    
    func testWhenEmojisArePresentInDomains_ThenTheseCanBePunycoded() {
        
        XCTAssertEqual("example.com".punycodeEncodedHostname, "example.com")
        XCTAssertEqual("Dax🤔.com".punycodeEncodedHostname, "xn--dax-v153b.com")
        XCTAssertEqual("🤔.com".punycodeEncodedHostname, "xn--wp9h.com")
    }

    func testThatIsValidHostReturnsTrueForValidDomains() {
        XCTAssertTrue("duckduckgo.com".isValidHost(validateDomain: true))
        XCTAssertTrue("gitub.io".isValidHost(validateDomain: true))
        XCTAssertTrue("foo.online".isValidHost(validateDomain: true))
        XCTAssertTrue("bar.uk.com".isValidHost(validateDomain: true))
        XCTAssertTrue("bar.uk".isValidHost(validateDomain: true))
        XCTAssertTrue("localhost".isValidHost(validateDomain: true))
        XCTAssertTrue("host.local".isValidHost(validateDomain: true))
    }

    func testThatIsValidHostReturnsFalseForInvalidDomains() {
        XCTAssertFalse("www".isValidHost(validateDomain: true))
        XCTAssertFalse("duckduckgo".isValidHost(validateDomain: true))
        XCTAssertFalse("local".isValidHost(validateDomain: true))
        XCTAssertFalse("localdomain".isValidHost(validateDomain: true))
        XCTAssertFalse("internal".isValidHost(validateDomain: true))
    }

    func testThatIsValidHostInNonStrictModeReturnsTrueForValidInput() {
        XCTAssertTrue("duckduckgo.com.internal".isValidHost(validateDomain: false))
        XCTAssertTrue("gitub.io.custom-domain".isValidHost(validateDomain: false))
        XCTAssertTrue("foo.online.localdomain".isValidHost(validateDomain: false))
        XCTAssertTrue("localdomain".isValidHost(validateDomain: false))
        XCTAssertTrue("internal".isValidHost(validateDomain: false))
    }

    func testThatIsValidHostInNonStrictModeReturnsFalseForInvalidInput() {
        XCTAssertFalse("duckduckgo.com.^internal".isValidHost(validateDomain: false))
        XCTAssertFalse("gitub.io.???.custom-domain".isValidHost(validateDomain: false))
        XCTAssertFalse("foo.online..localdomain".isValidHost(validateDomain: false))
        XCTAssertFalse("local%%domain".isValidHost(validateDomain: false))
        XCTAssertFalse("interna=l".isValidHost(validateDomain: false))
    }
}
