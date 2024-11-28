//
//  MaliciousSiteProtectionUpdateManagerTests.swift
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

class MaliciousSiteProtectionUpdateManagerTests: XCTestCase {
    var updateManager: MaliciousSiteProtection.UpdateManager!
    var dataManager: MaliciousSiteProtection.DataManaging!
    var apiClient: MaliciousSiteProtection.APIClient.Mockable!

    override func setUp() async throws {
        apiClient = MockMaliciousSiteProtectionAPIClient()
        dataManager = MockMaliciousSiteProtectionDataManager()
        updateManager = MaliciousSiteProtection.UpdateManager(apiClient: apiClient, dataManager: dataManager)
    }

    override func tearDown() {
        updateManager = nil
        dataManager = nil
        apiClient = nil
    }

    func testUpdateHashPrefixes() async {
        await updateManager.updateHashPrefixes()
        let dataSet = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        XCTAssertEqual(dataSet, HashPrefixSet(revision: 1, items: [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ]))
    }

    func testUpdateFilterSet() async {
        await updateManager.updateFilterSet()
        let dataSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        XCTAssertEqual(dataSet, FilterDictionary(revision: 1, items: [
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash2", regex: ".*test.*")
        ]))
    }

    func testRevision1AddsAndDeletesData() async {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash2", regex: ".*test.*"),
            Filter(hash: "testhash3", regex: ".*test.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "aa00bb11",
            "bb00cc11",
            "a379a6f6",
            "93e2435e"
        ]

        // revision 0 -> 1
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        // revision 1 -> 2
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 2, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 2, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    func testRevision2AddsAndDeletesData() async {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash4", regex: ".*test.*"),
            Filter(hash: "testhash2", regex: ".*test1.*"),
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash3", regex: ".*test3.*"),
        ]
        let expectedHashPrefixes: Set<String> = [
            "aa00bb11",
            "a379a6f6",
            "c0be0d0a6",
            "dd00ee11",
            "cc00dd11"
        ]

        // Save revision and update the filter set and hash prefixes
        await dataManager.store(FilterDictionary(revision: 2, items: [
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash2", regex: ".*test.*"),
            Filter(hash: "testhash2", regex: ".*test1.*"),
            Filter(hash: "testhash3", regex: ".*test3.*"),
        ]), for: .filterSet(threatKind: .phishing))
        await dataManager.store(HashPrefixSet(revision: 2, items: [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ]), for: .hashPrefixes(threatKind: .phishing))

        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 3, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 3, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    func testRevision3AddsAndDeletesNothing() async {
        let expectedFilterSet: Set<Filter> = []
        let expectedHashPrefixes: Set<String> = []

        // Save revision and update the filter set and hash prefixes
        await dataManager.store(FilterDictionary(revision: 3, items: []), for: .filterSet(threatKind: .phishing))
        await dataManager.store(HashPrefixSet(revision: 3, items: []), for: .hashPrefixes(threatKind: .phishing))

        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 3, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 3, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    func testRevision4AddsAndDeletesData() async {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash5", regex: ".*test.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "a379a6f6",
        ]

        // Save revision and update the filter set and hash prefixes
        await dataManager.store(FilterDictionary(revision: 4, items: []), for: .filterSet(threatKind: .phishing))
        await dataManager.store(HashPrefixSet(revision: 4, items: []), for: .hashPrefixes(threatKind: .phishing))

        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 5, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 5, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    func testRevision5replacesData() async {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash6", regex: ".*test6.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "aa55aa55"
        ]

        // Save revision and update the filter set and hash prefixes
        await dataManager.store(FilterDictionary(revision: 5, items: [
            Filter(hash: "testhash2", regex: ".*test.*"),
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash5", regex: ".*test.*")
        ]), for: .filterSet(threatKind: .phishing))
        await dataManager.store(HashPrefixSet(revision: 5, items: [
            "a379a6f6",
            "dd00ee11",
            "cc00dd11",
            "bb00cc11"
        ]), for: .hashPrefixes(threatKind: .phishing))

        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 6, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 6, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

}
