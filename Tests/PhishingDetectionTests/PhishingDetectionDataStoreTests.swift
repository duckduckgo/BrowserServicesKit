//
//  PhishingDetectionDataStoreTests.swift
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

class PhishingDetectionDataStoreTests: XCTestCase {
    var mockDataProvider: MockPhishingDetectionDataProvider!
    let datasetFiles: [String] = ["hashPrefixes.json", "filterSet.json", "revision.txt"]
    var dataStore: PhishingDetectionDataStore!
    var fileStorageManager: FileStorageManager!

    override func setUp() {
        super.setUp()
        mockDataProvider = MockPhishingDetectionDataProvider()
        fileStorageManager = MockPhishingFileStorageManager()
        dataStore = PhishingDetectionDataStore(dataProvider: mockDataProvider, fileStorageManager: fileStorageManager)
    }

    override func tearDown() {
        mockDataProvider = nil
        dataStore = nil
        super.tearDown()
    }

    func clearDatasets() {
        for fileName in datasetFiles {
            let emptyData = Data()
            fileStorageManager.write(data: emptyData, to: fileName)
        }
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

    func testWriteAndLoadData() async {
        // Get and write data
        let filterSet = dataStore.filterSet
        let hashPrefixes = dataStore.hashPrefixes
        let revision = dataStore.currentRevision
        dataStore.saveHashPrefixes(set: hashPrefixes)
        dataStore.saveFilterSet(set: filterSet)
        dataStore.saveRevision(revision)

        // Clear data in memory
        dataStore = PhishingDetectionDataStore(dataProvider: mockDataProvider, fileStorageManager: fileStorageManager)

        // Load data
        XCTAssertFalse(dataStore.hashPrefixes.isEmpty, "Hash prefixes should not be empty after load.")
        XCTAssertFalse(dataStore.filterSet.isEmpty, "Filter set should not be empty after load.")
    }
}
