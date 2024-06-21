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
@testable import Common

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

    func testHashedSuffix() {
        XCTAssertEqual("http://localhost:8084/#navlink".hashedSuffix, "#navlink")
        XCTAssertEqual("http://localhost:8084/#navlink#1".hashedSuffix, "#navlink#1")
        XCTAssertEqual("http://localhost:8084/#".hashedSuffix, "#")
        XCTAssertEqual("http://localhost:8084/##".hashedSuffix, "##")
        XCTAssertNil("http://localhost:8084/".hashedSuffix)
        XCTAssertNil("http://localhost:8084".hashedSuffix)
    }

    func testDroppingHashedSuffix() {
        XCTAssertEqual("http://localhost:8084/#navlink".droppingHashedSuffix(), "http://localhost:8084/")
        XCTAssertEqual("http://localhost:8084/#navlink#1".droppingHashedSuffix(), "http://localhost:8084/")
        XCTAssertEqual("about://blank/#navlink1".url!.absoluteString.droppingHashedSuffix(), "about://blank/")
        XCTAssertEqual("about:blank/#navlink1".url!.absoluteString.droppingHashedSuffix(), "about:blank/")
        XCTAssertEqual("about:blank#navlink1".url!.absoluteString.droppingHashedSuffix(), "about:blank")
    }

    func testToIPv4Host() {
        XCTAssertEqual("1.1.1.1".toIPv4Host, "1.1.1.1")
        XCTAssertEqual("1".toIPv4Host, "0.0.0.1")
        XCTAssertEqual("1.2".toIPv4Host, "1.0.0.2")
    }
}
