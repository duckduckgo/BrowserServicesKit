//
//  PhishingDetectionUpdateManagerTests.swift
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

class PhishingDetectionUpdateManagerTests: XCTestCase {
    var updateManager: PhishingDetectionUpdateManager!
    var dataStore: PhishingDetectionDataSaving!
    var mockClient: MockPhishingDetectionClient!

    override func setUp() {
        super.setUp()
        mockClient = MockPhishingDetectionClient()
        dataStore = MockPhishingDetectionDataStore()
        updateManager = PhishingDetectionUpdateManager(client: mockClient, dataStore: dataStore)
    }

    override func tearDown() {
        updateManager = nil
        dataStore = nil
        mockClient = nil
        super.tearDown()
    }
    
    func testUpdateHashPrefixes() async {
        await updateManager.updateHashPrefixes()
        XCTAssertFalse(dataStore.hashPrefixes.isEmpty, "Hash prefixes should not be empty after update.")
        XCTAssertEqual(dataStore.hashPrefixes, [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ])
    }

    func testUpdateFilterSet() async {
        await updateManager.updateFilterSet()
        XCTAssertFalse(dataStore.filterSet.isEmpty, "Filter set should not be empty after update.")
    }

    func testRevision1AddsData() async {
        dataStore.saveRevision(1)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()
        XCTAssertTrue(dataStore.filterSet.contains(where: { $0.hashValue == "testhash3" }), "Filter set should contain added data after update.")
        XCTAssertTrue(dataStore.hashPrefixes.contains("93e2435e"), "Hash prefixes should contain added data after update.")
    }

    func testRevision2AddsAndDeletesData() async {
        dataStore.saveRevision(2)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()
        XCTAssertFalse(dataStore.filterSet.contains(where: { $0.hashValue == "testhash2" }), "Filter set should not contain deleted data after update.")
        XCTAssertFalse(dataStore.hashPrefixes.contains("bb00cc11"), "Hash prefixes should not contain deleted data after update.")
        XCTAssertTrue(dataStore.hashPrefixes.contains("c0be0d0a6"))
    }

    func testRevision4AddsAndDeletesData() async {
        dataStore.saveRevision(4)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()
        XCTAssertTrue(dataStore.filterSet.contains(where: { $0.hashValue == "testhash5" }), "Filter set should contain added data after update.")
        XCTAssertFalse(dataStore.filterSet.contains(where: { $0.hashValue == "testhash3" }), "Filter set should not contain deleted data after update.")
        XCTAssertTrue(dataStore.hashPrefixes.contains("a379a6f6"), "Hash prefixes should contain added data after update.")
        XCTAssertFalse(dataStore.hashPrefixes.contains("aa00bb11"), "Hash prefixes should not contain deleted data after update.")
    }
}

class MockPhishingFileStorageManager: FileStorageManager {
    private var data: [String: Data] = [:]

    func write(data: Data, to filename: String) {
        self.data[filename] = data
    }

    func read(from filename: String) -> Data? {
        return data[filename]
    }
}
