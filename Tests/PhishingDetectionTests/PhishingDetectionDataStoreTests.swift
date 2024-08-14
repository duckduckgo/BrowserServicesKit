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

    func testWhenNoDataSavedThenProviderDataReturned() async {
        clearDatasets()
        let expectedFilerSet = Set([Filter(hashValue: "some", regex: "some")])
        let expectedHashPrefix = Set(["sassa"])
        mockDataProvider.shouldReturnFilterSet(set: expectedFilerSet)
        mockDataProvider.shouldReturnHashPrefixes(set: expectedHashPrefix)

        let actualFilterSet = dataStore.filterSet
        let actualHashPrefix = dataStore.hashPrefixes

        XCTAssertEqual(actualFilterSet, expectedFilerSet)
        XCTAssertEqual(actualHashPrefix, expectedHashPrefix)
    }

    func testWriteAndLoadData() async {
        // Get and write data
        let expectedHashPrefixes = Set(["aabb"])
        let expectedFilterSet = Set([Filter(hashValue: "dummyhash", regex: "dummyregex")])
        let expectedRevision = 65

        dataStore.saveHashPrefixes(set: expectedHashPrefixes)
        dataStore.saveFilterSet(set: expectedFilterSet)
        dataStore.saveRevision(expectedRevision)

        XCTAssertEqual(dataStore.filterSet, expectedFilterSet)
        XCTAssertEqual(dataStore.hashPrefixes, expectedHashPrefixes)
        XCTAssertEqual(dataStore.currentRevision, expectedRevision)

        // Test decode JSON data to expected types
        let storedHashPrefixesData = fileStorageManager.read(from: "hashPrefixes.json")
        let storedFilterSetData = fileStorageManager.read(from: "filterSet.json")
        let storedRevisionData = fileStorageManager.read(from: "revision.txt")

        let decoder = JSONDecoder()
        if let storedHashPrefixes = try? decoder.decode(Set<String>.self, from: storedHashPrefixesData!),
           let storedFilterSet = try? decoder.decode(Set<Filter>.self, from: storedFilterSetData!),
           let storedRevisionString = String(data: storedRevisionData!, encoding: .utf8),
           let storedRevision = Int(storedRevisionString.trimmingCharacters(in: .whitespacesAndNewlines)) {

            XCTAssertEqual(storedFilterSet, expectedFilterSet)
            XCTAssertEqual(storedHashPrefixes, expectedHashPrefixes)
            XCTAssertEqual(storedRevision, expectedRevision)
        } else {
            XCTFail("Failed to decode stored PhishingDetection data")
        }
    }
}
