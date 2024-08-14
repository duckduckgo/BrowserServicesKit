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

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockPhishingDetectionClient()
        dataStore = MockPhishingDetectionDataStore()
        updateManager = PhishingDetectionUpdateManager(client: mockClient, dataStore: dataStore)
        dataStore.saveRevision(0)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()
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
        XCTAssertEqual(dataStore.filterSet, [
            Filter(hashValue: "testhash1", regex: ".*example.*"),
            Filter(hashValue: "testhash2", regex: ".*test.*")
        ])
    }

    func testRevision1AddsAndDeletesData() async {
        let expectedFilterSet: Set<Filter> = [
            Filter(hashValue: "testhash2", regex: ".*test.*"),
            Filter(hashValue: "testhash3", regex: ".*test.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "aa00bb11",
            "bb00cc11",
            "a379a6f6",
            "93e2435e"
        ]

        // Save revision and update the filter set and hash prefixes
        dataStore.saveRevision(1)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        XCTAssertEqual(dataStore.filterSet, expectedFilterSet, "Filter set should match the expected set after update.")
        XCTAssertEqual(dataStore.hashPrefixes, expectedHashPrefixes, "Hash prefixes should match the expected set after update.")
    }

    func testRevision2AddsAndDeletesData() async {
        let expectedFilterSet: Set<Filter> = [
            Filter(hashValue: "testhash4", regex: ".*test.*"),
            Filter(hashValue: "testhash1", regex: ".*example.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "aa00bb11",
            "a379a6f6",
            "c0be0d0a6",
            "dd00ee11",
            "cc00dd11"
        ]

        // Save revision and update the filter set and hash prefixes
        dataStore.saveRevision(2)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        XCTAssertEqual(dataStore.filterSet, expectedFilterSet, "Filter set should match the expected set after update.")
        XCTAssertEqual(dataStore.hashPrefixes, expectedHashPrefixes, "Hash prefixes should match the expected set after update.")
    }

    func testRevision3AddsAndDeletesNothing() async {
        let expectedFilterSet = dataStore.filterSet
        let expectedHashPrefixes = dataStore.hashPrefixes

        // Save revision and update the filter set and hash prefixes
        dataStore.saveRevision(3)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        XCTAssertEqual(dataStore.filterSet, expectedFilterSet, "Filter set should match the expected set after update.")
        XCTAssertEqual(dataStore.hashPrefixes, expectedHashPrefixes, "Hash prefixes should match the expected set after update.")
    }

    func testRevision4AddsAndDeletesData() async {
        let expectedFilterSet: Set<Filter> = [
            Filter(hashValue: "testhash2", regex: ".*test.*"),
            Filter(hashValue: "testhash1", regex: ".*example.*"),
            Filter(hashValue: "testhash5", regex: ".*test.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "a379a6f6",
            "dd00ee11",
            "cc00dd11",
            "bb00cc11"
        ]

        // Save revision and update the filter set and hash prefixes
        dataStore.saveRevision(4)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        XCTAssertEqual(dataStore.filterSet, expectedFilterSet, "Filter set should match the expected set after update.")
        XCTAssertEqual(dataStore.hashPrefixes, expectedHashPrefixes, "Hash prefixes should match the expected set after update.")
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
