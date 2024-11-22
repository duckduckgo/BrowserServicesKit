//
//  MaliciousSiteDetectorTests.swift
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

class MaliciousSiteDetectorTests: XCTestCase {

    private var mockAPIClient: MockMaliciousSiteProtectionAPIClient!
    private var mockDataManager: MockMaliciousSiteProtectionDataManager!
    private var mockEventMapping: MockEventMapping!
    private var detector: MaliciousSiteDetector!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockMaliciousSiteProtectionAPIClient()
        mockDataManager = MockMaliciousSiteProtectionDataManager()
        mockEventMapping = MockEventMapping()
        detector = MaliciousSiteDetector(apiClient: mockAPIClient, dataManager: mockDataManager, eventMapping: mockEventMapping)
    }

    override func tearDown() {
        mockAPIClient = nil
        mockDataManager = nil
        mockEventMapping = nil
        detector = nil
        super.tearDown()
    }

    func testIsMaliciousWithLocalFilterHit() async {
        let filter = Filter(hash: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d", regex: ".*malicious.*")
        mockDataManager.filterSet = Set([filter])
        mockDataManager.hashPrefixes = Set(["255a8a79"])

        let url = URL(string: "https://malicious.com/")!

        let result = await detector.evaluate(url)

        XCTAssertEqual(result, .phishing)
    }

    func testIsMaliciousWithApiMatch() async {
        mockDataManager.filterSet = Set()
        mockDataManager.hashPrefixes = ["a379a6f6"]

        let url = URL(string: "https://example.com/mal")!

        let result = await detector.evaluate(url)

        XCTAssertEqual(result, .phishing)
    }

    func testIsMaliciousWithHashPrefixMatch() async {
        let filter = Filter(hash: "notamatch", regex: ".*malicious.*")
        mockDataManager.filterSet = [filter]
        mockDataManager.hashPrefixes = ["4c64eb24"] // matches safe.com

        let url = URL(string: "https://safe.com")!

        let result = await detector.evaluate(url)

        XCTAssertNil(result)
    }

    func testIsMaliciousWithFullHashMatch() async {
        // 4c64eb2468bcd3e113b37167e6b819aeccf550f974a6082ef17fb74ca68e823b
        let filter = Filter(hash: "4c64eb2468bcd3e113b37167e6b819aeccf550f974a6082ef17fb74ca68e823b", regex: "https://safe.com/maliciousURI")
        mockDataManager.filterSet = [filter]
        mockDataManager.hashPrefixes = ["4c64eb24"]

        let url = URL(string: "https://safe.com")!

        let result = await detector.evaluate(url)

        XCTAssertNil(result)
    }

    func testIsMaliciousWithNoHashPrefixMatch() async {
        let filter = Filter(hash: "testHash", regex: ".*malicious.*")
        mockDataManager.filterSet = [filter]
        mockDataManager.hashPrefixes = ["testPrefix"]

        let url = URL(string: "https://safe.com")!

        let result = await detector.evaluate(url)

        XCTAssertNil(result)
    }
}
