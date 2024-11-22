//
//  MaliciousSiteProtectionDataManagerTests.swift
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

class MaliciousSiteProtectionDataManagerTests: XCTestCase {
    var embeddedDataProvider: MockMaliciousSiteProtectionEmbeddedDataProvider!
    enum Constants {
        static let hashPrefixesFileName = "phishingHashPrefixes.json"
        static let filterSetFileName = "phishingFilterSet.json"
    }
    let datasetFiles: [String] = [Constants.hashPrefixesFileName, Constants.filterSetFileName, "revision.txt"]
    var dataManager: MaliciousSiteProtection.DataManager!
    var fileStore: MaliciousSiteProtection.FileStoring!

    override func setUp() {
        super.setUp()
        embeddedDataProvider = MockMaliciousSiteProtectionEmbeddedDataProvider()
        fileStore = MockMaliciousSiteProtectionFileStore()
        dataManager = MaliciousSiteProtection.DataManager(embeddedDataProvider: embeddedDataProvider, fileStore: fileStore)
    }

    override func tearDown() {
        embeddedDataProvider = nil
        dataManager = nil
        super.tearDown()
    }

    func clearDatasets() {
        for fileName in datasetFiles {
            let emptyData = Data()
            fileStore.write(data: emptyData, to: fileName)
        }
    }

    func testWhenNoDataSavedThenProviderDataReturned() async {
        clearDatasets()
        let expectedFilerSet = Set([Filter(hash: "some", regex: "some")])
        let expectedHashPrefix = Set(["sassa"])
        embeddedDataProvider.shouldReturnFilterSet(set: expectedFilerSet)
        embeddedDataProvider.shouldReturnHashPrefixes(set: expectedHashPrefix)

        let actualFilterSet = dataManager.filterSet
        let actualHashPrefix = dataManager.hashPrefixes

        XCTAssertEqual(actualFilterSet, expectedFilerSet)
        XCTAssertEqual(actualHashPrefix, expectedHashPrefix)
    }

    func testWhenEmbeddedRevisionNewerThanOnDisk_ThenLoadEmbedded() async {
        let encoder = JSONEncoder()
        // On Disk Data Setup
        fileStore.write(data: "1".utf8data, to: "revision.txt")
        let onDiskFilterSet = Set([Filter(hash: "other", regex: "other")])
        let filterSetData = try! encoder.encode(Array(onDiskFilterSet))
        let onDiskHashPrefix = Set(["faffa"])
        let hashPrefixData = try! encoder.encode(Array(onDiskHashPrefix))
        fileStore.write(data: filterSetData, to: Constants.filterSetFileName)
        fileStore.write(data: hashPrefixData, to: Constants.hashPrefixesFileName)

        // Embedded Data Setup
        embeddedDataProvider.embeddedRevision = 5
        let embeddedFilterSet = Set([Filter(hash: "some", regex: "some")])
        let embeddedHashPrefix = Set(["sassa"])
        embeddedDataProvider.shouldReturnFilterSet(set: embeddedFilterSet)
        embeddedDataProvider.shouldReturnHashPrefixes(set: embeddedHashPrefix)

        let actualRevision = dataManager.currentRevision
        let actualFilterSet = dataManager.filterSet
        let actualHashPrefix = dataManager.hashPrefixes

        XCTAssertEqual(actualFilterSet, embeddedFilterSet)
        XCTAssertEqual(actualHashPrefix, embeddedHashPrefix)
        XCTAssertEqual(actualRevision, 5)
    }

    func testWhenEmbeddedRevisionOlderThanOnDisk_ThenDontLoadEmbedded() async {
        let encoder = JSONEncoder()
        // On Disk Data Setup
        fileStore.write(data: "6".utf8data, to: "revision.txt")
        let onDiskFilterSet = Set([Filter(hash: "other", regex: "other")])
        let filterSetData = try! encoder.encode(Array(onDiskFilterSet))
        let onDiskHashPrefix = Set(["faffa"])
        let hashPrefixData = try! encoder.encode(Array(onDiskHashPrefix))
        fileStore.write(data: filterSetData, to: Constants.filterSetFileName)
        fileStore.write(data: hashPrefixData, to: Constants.hashPrefixesFileName)

        // Embedded Data Setup
        embeddedDataProvider.embeddedRevision = 1
        let embeddedFilterSet = Set([Filter(hash: "some", regex: "some")])
        let embeddedHashPrefix = Set(["sassa"])
        embeddedDataProvider.shouldReturnFilterSet(set: embeddedFilterSet)
        embeddedDataProvider.shouldReturnHashPrefixes(set: embeddedHashPrefix)

        let actualRevision = dataManager.currentRevision
        let actualFilterSet = dataManager.filterSet
        let actualHashPrefix = dataManager.hashPrefixes

        XCTAssertEqual(actualFilterSet, onDiskFilterSet)
        XCTAssertEqual(actualHashPrefix, onDiskHashPrefix)
        XCTAssertEqual(actualRevision, 6)
    }

    func testWriteAndLoadData() async {
        // Get and write data
        let expectedHashPrefixes = Set(["aabb"])
        let expectedFilterSet = Set([Filter(hash: "dummyhash", regex: "dummyregex")])
        let expectedRevision = 65

        dataManager.saveHashPrefixes(set: expectedHashPrefixes)
        dataManager.saveFilterSet(set: expectedFilterSet)
        dataManager.saveRevision(expectedRevision)

        XCTAssertEqual(dataManager.filterSet, expectedFilterSet)
        XCTAssertEqual(dataManager.hashPrefixes, expectedHashPrefixes)
        XCTAssertEqual(dataManager.currentRevision, expectedRevision)

        // Test decode JSON data to expected types
        let storedHashPrefixesData = fileStore.read(from: Constants.hashPrefixesFileName)
        let storedFilterSetData = fileStore.read(from: Constants.filterSetFileName)
        let storedRevisionData = fileStore.read(from: "revision.txt")

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

    func testLazyLoadingDoesNotReturnStaleData() async {
        clearDatasets()

        // Set up initial data
        let initialFilterSet = Set([Filter(hash: "initial", regex: "initial")])
        let initialHashPrefixes = Set(["initialPrefix"])
        embeddedDataProvider.shouldReturnFilterSet(set: initialFilterSet)
        embeddedDataProvider.shouldReturnHashPrefixes(set: initialHashPrefixes)

        // Access the lazy-loaded properties to trigger loading
        let loadedFilterSet = dataManager.filterSet
        let loadedHashPrefixes = dataManager.hashPrefixes

        // Validate loaded data matches initial data
        XCTAssertEqual(loadedFilterSet, initialFilterSet)
        XCTAssertEqual(loadedHashPrefixes, initialHashPrefixes)

        // Update in-memory data
        let updatedFilterSet = Set([Filter(hash: "updated", regex: "updated")])
        let updatedHashPrefixes = Set(["updatedPrefix"])
        dataManager.saveFilterSet(set: updatedFilterSet)
        dataManager.saveHashPrefixes(set: updatedHashPrefixes)

        // Access lazy-loaded properties again
        let reloadedFilterSet = dataManager.filterSet
        let reloadedHashPrefixes = dataManager.hashPrefixes

        // Validate reloaded data matches updated data
        XCTAssertEqual(reloadedFilterSet, updatedFilterSet)
        XCTAssertEqual(reloadedHashPrefixes, updatedHashPrefixes)

        // Validate on-disk data is also updated
        let storedFilterSetData = fileStore.read(from: Constants.filterSetFileName)
        let storedHashPrefixesData = fileStore.read(from: Constants.hashPrefixesFileName)

        let decoder = JSONDecoder()
        if let storedFilterSet = try? decoder.decode(Set<Filter>.self, from: storedFilterSetData!),
           let storedHashPrefixes = try? decoder.decode(Set<String>.self, from: storedHashPrefixesData!) {

            XCTAssertEqual(storedFilterSet, updatedFilterSet)
            XCTAssertEqual(storedHashPrefixes, updatedHashPrefixes)
        } else {
            XCTFail("Failed to decode stored PhishingDetection data after update")
        }
    }

}

class MockMaliciousSiteProtectionFileStore: MaliciousSiteProtection.FileStoring {
    private var data: [String: Data] = [:]

    func write(data: Data, to filename: String) {
        self.data[filename] = data
    }

    func read(from filename: String) -> Data? {
        return data[filename]
    }
}
