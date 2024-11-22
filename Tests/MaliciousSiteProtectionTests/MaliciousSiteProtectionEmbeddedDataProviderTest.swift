//
//  MaliciousSiteProtectionEmbeddedDataProviderTest.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

@testable import MaliciousSiteProtection

class MaliciousSiteProtectionEmbeddedDataProviderTest: XCTestCase {
    var filterSetURL: URL!
    var hashPrefixURL: URL!
    var dataProvider: MaliciousSiteProtection.EmbeddedDataProvider!

    override func setUp() {
        super.setUp()
        filterSetURL = Bundle.module.url(forResource: "phishingFilterSet", withExtension: "json")!
        hashPrefixURL = Bundle.module.url(forResource: "phishingHashPrefixes", withExtension: "json")!
    }

    override func tearDown() {
        filterSetURL = nil
        hashPrefixURL = nil
        dataProvider = nil
        super.tearDown()
    }

    func testDataProviderLoadsJSON() {
        dataProvider = .init(revision: 0, filterSetURL: filterSetURL, filterSetDataSHA: "4fd2868a4f264501ec175ab866504a2a96c8d21a3b5195b405a4a83b51eae504", hashPrefixURL: hashPrefixURL, hashPrefixDataSHA: "21b047a9950fcaf86034a6b16181e18815cb8d276386d85c8977ca8c5f8aa05f")
        let expectedFilter = Filter(hash: "e4753ddad954dafd4ff4ef67f82b3c1a2db6ef4a51bda43513260170e558bd13", regex: "(?i)^https?\\:\\/\\/privacy-test-pages\\.site(?:\\:(?:80|443))?\\/security\\/badware\\/phishing\\.html$")
        XCTAssertTrue(dataProvider.loadEmbeddedFilterSet().contains(expectedFilter))
        XCTAssertTrue(dataProvider.loadEmbeddedHashPrefixes().contains("012db806"))
    }

}
