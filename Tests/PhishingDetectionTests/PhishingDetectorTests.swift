//
//  PhishingDetectorTests.swift
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
@testable import PhishingDetection

class IsMaliciousTests: XCTestCase {
    func testIsMaliciousWithLocalFilterHit() async {
        let mockAPIClient = MockPhishingDetectionClient()
        let mockDataStore = MockPhishingDetectionDataStore()
        let detector = PhishingDetector(apiClient: mockAPIClient, dataStore: mockDataStore)
        let filter = Filter(hashValue: "255a8a793097aeea1f06a19c08cde28db0eb34c660c6e4e7480c9525d034b16d", regex: ".*malicious.*")
        mockDataStore.filterSet = Set([filter])
        mockDataStore.hashPrefixes = Set(["255a8a79"])

        let url = URL(string: "https://malicious.com/")!

        let result = await detector.isMalicious(url: url)

        XCTAssertTrue(result)
    }

    func testIsMaliciousWithApiMatch() async {
        let mockAPIClient = MockPhishingDetectionClient()
        let mockDataStore = MockPhishingDetectionDataStore()
        let detector = PhishingDetector(apiClient: mockAPIClient, dataStore: mockDataStore)
        mockDataStore.filterSet = Set()
        mockDataStore.hashPrefixes = ["a379a6f6"]

        let url = URL(string: "https://example.com/mal")!

        let result = await detector.isMalicious(url: url)

        XCTAssertTrue(result)
    }

    func testIsMaliciousWithNoMatch() async {
        let mockAPIClient = MockPhishingDetectionClient()
        let mockDataStore = MockPhishingDetectionDataStore()
        let detector = PhishingDetector(apiClient: mockAPIClient, dataStore: mockDataStore)
        let filter = Filter(hashValue: "testHash", regex: ".*malicious.*")
        mockDataStore.filterSet = [filter]
        mockDataStore.hashPrefixes = ["testPrefix"]

        let url = URL(string: "https://safe.com")!

        let result = await detector.isMalicious(url: url)

        XCTAssertFalse(result)
    }
}
