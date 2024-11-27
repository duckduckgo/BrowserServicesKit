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
    let datasetFiles: [String] = [Constants.hashPrefixesFileName, Constants.filterSetFileName]
    var dataManager: MaliciousSiteProtection.DataManager!
    var fileStore: MaliciousSiteProtection.FileStoring!

    override func setUp() async throws {
        embeddedDataProvider = MockMaliciousSiteProtectionEmbeddedDataProvider()
        fileStore = MockMaliciousSiteProtectionFileStore()
        setUpDataManager()
    }

    func setUpDataManager() {
        dataManager = MaliciousSiteProtection.DataManager(fileStore: fileStore, embeddedDataProvider: embeddedDataProvider, fileNameProvider: { dataType in
            switch dataType {
            case .filterSet: Constants.filterSetFileName
            case .hashPrefixSet: Constants.hashPrefixesFileName
            }
        })
    }

    override func tearDown() async throws {
        embeddedDataProvider = nil
        dataManager = nil
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
        let expectedFilerDict = FilterDictionary(revision: 65, items: expectedFilerSet)
        let expectedHashPrefix = Set(["sassa"])
        embeddedDataProvider.filterSet = expectedFilerSet
        embeddedDataProvider.hashPrefixes = expectedHashPrefix

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))

        XCTAssertEqual(actualFilterSet, expectedFilerDict)
        XCTAssertEqual(actualHashPrefix.set, expectedHashPrefix)
    }

    func testWhenEmbeddedRevisionNewerThanOnDisk_ThenLoadEmbedded() async {
        let encoder = JSONEncoder()
        // On Disk Data Setup
        let onDiskFilterSet = Set([Filter(hash: "other", regex: "other")])
        let filterSetData = try! encoder.encode(Array(onDiskFilterSet))
        let onDiskHashPrefix = Set(["faffa"])
        let hashPrefixData = try! encoder.encode(Array(onDiskHashPrefix))
        fileStore.write(data: filterSetData, to: Constants.filterSetFileName)
        fileStore.write(data: hashPrefixData, to: Constants.hashPrefixesFileName)

        // Embedded Data Setup
        embeddedDataProvider.embeddedRevision = 5
        let embeddedFilterSet = Set([Filter(hash: "some", regex: "some")])
        let embeddedFilterDict = FilterDictionary(revision: 5, items: embeddedFilterSet)
        let embeddedHashPrefix = Set(["sassa"])
        embeddedDataProvider.filterSet = embeddedFilterSet
        embeddedDataProvider.hashPrefixes = embeddedHashPrefix

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, embeddedFilterDict)
        XCTAssertEqual(actualHashPrefix.set, embeddedHashPrefix)
        XCTAssertEqual(actualFilterSetRevision, 5)
        XCTAssertEqual(actualHashPrefixRevision, 5)
    }

    func testWhenEmbeddedRevisionOlderThanOnDisk_ThenDontLoadEmbedded() async {
        // On Disk Data Setup
        let onDiskFilterDict = FilterDictionary(revision: 6, items: [Filter(hash: "other", regex: "other")])
        let filterSetData = try! JSONEncoder().encode(onDiskFilterDict)
        let onDiskHashPrefix = HashPrefixSet(revision: 6, items: ["faffa"])
        let hashPrefixData = try! JSONEncoder().encode(onDiskHashPrefix)
        fileStore.write(data: filterSetData, to: Constants.filterSetFileName)
        fileStore.write(data: hashPrefixData, to: Constants.hashPrefixesFileName)

        // Embedded Data Setup
        embeddedDataProvider.embeddedRevision = 1
        let embeddedFilterSet = Set([Filter(hash: "some", regex: "some")])
        let embeddedHashPrefix = Set(["sassa"])
        embeddedDataProvider.filterSet = embeddedFilterSet
        embeddedDataProvider.hashPrefixes = embeddedHashPrefix

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, onDiskFilterDict)
        XCTAssertEqual(actualHashPrefix, onDiskHashPrefix)
        XCTAssertEqual(actualFilterSetRevision, 6)
        XCTAssertEqual(actualHashPrefixRevision, 6)
    }

    func testWhenStoredDataIsMalformed_ThenEmbeddedDataIsLoaded() async {
        // On Disk Data Setup
        fileStore.write(data: "fake".utf8data, to: Constants.filterSetFileName)
        fileStore.write(data: "fake".utf8data, to: Constants.hashPrefixesFileName)

        // Embedded Data Setup
        embeddedDataProvider.embeddedRevision = 1
        let embeddedFilterSet = Set([Filter(hash: "some", regex: "some")])
        let embeddedFilterDict = FilterDictionary(revision: 1, items: embeddedFilterSet)
        let embeddedHashPrefix = Set(["sassa"])
        embeddedDataProvider.filterSet = embeddedFilterSet
        embeddedDataProvider.hashPrefixes = embeddedHashPrefix

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, embeddedFilterDict)
        XCTAssertEqual(actualHashPrefix.set, embeddedHashPrefix)
        XCTAssertEqual(actualFilterSetRevision, 1)
        XCTAssertEqual(actualHashPrefixRevision, 1)
    }

    func testWriteAndLoadData() async {
        // Get and write data
        let expectedHashPrefixes = Set(["aabb"])
        let expectedFilterSet = Set([Filter(hash: "dummyhash", regex: "dummyregex")])
        let expectedRevision = 65

        await dataManager.store(HashPrefixSet(revision: expectedRevision, items: expectedHashPrefixes), for: .hashPrefixes(threatKind: .phishing))
        await dataManager.store(FilterDictionary(revision: expectedRevision, items: expectedFilterSet), for: .filterSet(threatKind: .phishing))

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, FilterDictionary(revision: expectedRevision, items: expectedFilterSet))
        XCTAssertEqual(actualHashPrefix.set, expectedHashPrefixes)
        XCTAssertEqual(actualFilterSetRevision, 65)
        XCTAssertEqual(actualHashPrefixRevision, 65)

        // Test reloading data
        setUpDataManager()

        let reloadedFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let reloadedHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let reloadedFilterSetRevision = actualFilterSet.revision
        let reloadedHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(reloadedFilterSet, FilterDictionary(revision: expectedRevision, items: expectedFilterSet))
        XCTAssertEqual(reloadedHashPrefix.set, expectedHashPrefixes)
        XCTAssertEqual(reloadedFilterSetRevision, 65)
        XCTAssertEqual(reloadedHashPrefixRevision, 65)
    }

    func testLazyLoadingDoesNotReturnStaleData() async {
        clearDatasets()

        // Set up initial data
        let initialFilterSet = Set([Filter(hash: "initial", regex: "initial")])
        let initialHashPrefixes = Set(["initialPrefix"])
        embeddedDataProvider.filterSet = initialFilterSet
        embeddedDataProvider.hashPrefixes = initialHashPrefixes

        // Access the lazy-loaded properties to trigger loading
        let loadedFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let loadedHashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))

        // Validate loaded data matches initial data
        XCTAssertEqual(loadedFilterSet, FilterDictionary(revision: 65, items: initialFilterSet))
        XCTAssertEqual(loadedHashPrefixes.set, initialHashPrefixes)

        // Update in-memory data
        let updatedFilterSet = Set([Filter(hash: "updated", regex: "updated")])
        let updatedHashPrefixes = Set(["updatedPrefix"])
        await dataManager.store(HashPrefixSet(revision: 1, items: updatedHashPrefixes), for: .hashPrefixes(threatKind: .phishing))
        await dataManager.store(FilterDictionary(revision: 1, items: updatedFilterSet), for: .filterSet(threatKind: .phishing))

        let actualFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let actualHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let actualFilterSetRevision = actualFilterSet.revision
        let actualHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(actualFilterSet, FilterDictionary(revision: 1, items: updatedFilterSet))
        XCTAssertEqual(actualHashPrefix.set, updatedHashPrefixes)
        XCTAssertEqual(actualFilterSetRevision, 1)
        XCTAssertEqual(actualHashPrefixRevision, 1)

        // Test reloading data – embedded data should be returned as its revision is greater
        setUpDataManager()

        let reloadedFilterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        let reloadedHashPrefix = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let reloadedFilterSetRevision = actualFilterSet.revision
        let reloadedHashPrefixRevision = actualFilterSet.revision

        XCTAssertEqual(reloadedFilterSet, FilterDictionary(revision: 65, items: initialFilterSet))
        XCTAssertEqual(reloadedHashPrefix.set, initialHashPrefixes)
        XCTAssertEqual(reloadedFilterSetRevision, 1)
        XCTAssertEqual(reloadedHashPrefixRevision, 1)
    }

}

class MockMaliciousSiteProtectionFileStore: MaliciousSiteProtection.FileStoring {

    private var data: [String: Data] = [:]

    func write(data: Data, to filename: String) -> Bool {
        self.data[filename] = data
        return true
    }

    func read(from filename: String) -> Data? {
        return data[filename]
    }
}