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
    var updateManager: PhishingDetectionUpdateManaging!
    var mockClient: MockPhishingDetectionClient!
    var mockDataProvider: MockPhishingDetectionDataProvider!
    let datasetFiles: [String] = ["hashPrefixes.json", "filterSet.json", "revision.txt"]
    var dataStore: PhishingDetectionDataStore!
    var fileStorageManager: FileStorageManaging!

    override func setUp() {
        super.setUp()
        mockClient = MockPhishingDetectionClient()
        mockDataProvider = MockPhishingDetectionDataProvider()
        fileStorageManager = FileStorageManager()
        dataStore = PhishingDetectionDataStore(dataProvider: mockDataProvider, fileStorageManager: fileStorageManager)
        updateManager = PhishingDetectionUpdateManager(client: mockClient, dataStore: dataStore)
    }

    override func tearDown() {
        mockClient = nil
        mockDataProvider = nil
        dataStore = nil
        updateManager = nil
        super.tearDown()
    }

    func clearDatasets() {
        for fileName in datasetFiles {
            let emptyData = Data()
            let fileURL = fileStorageManager.write(data: emptyData, to: fileName)
        }
    }

    func testUpdateFilterSet() async {
        await updateManager.updateFilterSet()
        XCTAssertFalse(dataStore.filterSet.isEmpty, "Filter set should not be empty after update.")
    }

    func testLoadDataError() async {
        clearDatasets()

        // Force load data
        _ = dataStore.filterSet
        _ = dataStore.hashPrefixes

        // Error => reload from embedded data
        XCTAssertTrue(mockDataProvider.loadFilterSetCalled)
        XCTAssertTrue(mockDataProvider.loadHashPrefixesCalled)
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

    func testWriteAndLoadData() async {
        // Get and write data
        _ = dataStore.filterSet
        _ = dataStore.hashPrefixes
        _ = dataStore.currentRevision
        dataStore.writeHashPrefixes()
        dataStore.writeFilterSet()
        dataStore.writeRevision()

        // Clear data
        dataStore = PhishingDetectionDataStore(dataProvider: mockDataProvider, fileStorageManager: fileStorageManager)

        // Load data
        await dataStore.loadData()
        XCTAssertFalse(dataStore.hashPrefixes.isEmpty, "Hash prefixes should not be empty after load.")
        XCTAssertFalse(dataStore.filterSet.isEmpty, "Filter set should not be empty after load.")
    }

    func testRevision1AddsData() async {
        dataStore.currentRevision = 1
        XCTAssertTrue(dataStore.filterSet.contains(where: { $0.hashValue == "testhash3" }), "Filter set should contain added data after update.")
        XCTAssertTrue(dataStore.hashPrefixes.contains("93e2435e"), "Hash prefixes should contain added data after update.")
    }

    func testRevision2AddsAndDeletesData() async {
        dataStore.currentRevision = 2
        XCTAssertFalse(dataStore.filterSet.contains(where: { $0.hashValue == "testhash2" }), "Filter set should not contain deleted data after update.")
        XCTAssertFalse(dataStore.hashPrefixes.contains("bb00cc11"), "Hash prefixes should not contain deleted data after update.")
        XCTAssertTrue(dataStore.hashPrefixes.contains("c0be0d0a6"))
    }

    func testRevision4AddsAndDeletesData() async {
        dataStore.currentRevision = 4
        XCTAssertTrue(dataStore.filterSet.contains(where: { $0.hashValue == "testhash5" }), "Filter set should contain added data after update.")
        XCTAssertFalse(dataStore.filterSet.contains(where: { $0.hashValue == "testhash3" }), "Filter set should not contain deleted data after update.")
        XCTAssertTrue(dataStore.hashPrefixes.contains("a379a6f6"), "Hash prefixes should contain added data after update.")
        XCTAssertFalse(dataStore.hashPrefixes.contains("aa00bb11"), "Hash prefixes should not contain deleted data after update.")
    }
}

// Extend dataStore to expose setting currentRevision for testing
extension PhishingDetectionDataStore {
    var currentRevision: Int {
        get { _currentRevision }
        set { _currentRevision = newValue }
    }
}
