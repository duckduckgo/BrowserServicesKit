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
    var apiClient: MaliciousSiteProtection.APIClientProtocol!

    override func setUp() async throws {
        try await super.setUp()
        apiClient = MockMaliciousSiteProtectionAPIClient()
        dataManager = MockMaliciousSiteProtectionDataManager()
        updateManager = MaliciousSiteProtection.UpdateManager(apiClient: apiClient, dataManager: dataManager)
        dataManager.saveRevision(0)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()
    }

    override func tearDown() {
        updateManager = nil
        dataManager = nil
        apiClient = nil
        super.tearDown()
    }

    func testUpdateHashPrefixes() async {
        await updateManager.updateHashPrefixes()
        XCTAssertFalse(dataManager.hashPrefixes.isEmpty, "Hash prefixes should not be empty after update.")
        XCTAssertEqual(dataManager.hashPrefixes, [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ])
    }

    func testUpdateFilterSet() async {
        await updateManager.updateFilterSet()
        XCTAssertEqual(dataManager.filterSet, [
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash2", regex: ".*test.*")
        ])
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

        // Save revision and update the filter set and hash prefixes
        dataManager.saveRevision(1)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        XCTAssertEqual(dataManager.filterSet, expectedFilterSet, "Filter set should match the expected set after update.")
        XCTAssertEqual(dataManager.hashPrefixes, expectedHashPrefixes, "Hash prefixes should match the expected set after update.")
    }

    func testRevision2AddsAndDeletesData() async {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash4", regex: ".*test.*"),
            Filter(hash: "testhash1", regex: ".*example.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "aa00bb11",
            "a379a6f6",
            "c0be0d0a6",
            "dd00ee11",
            "cc00dd11"
        ]

        // Save revision and update the filter set and hash prefixes
        dataManager.saveRevision(2)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        XCTAssertEqual(dataManager.filterSet, expectedFilterSet, "Filter set should match the expected set after update.")
        XCTAssertEqual(dataManager.hashPrefixes, expectedHashPrefixes, "Hash prefixes should match the expected set after update.")
    }

    func testRevision3AddsAndDeletesNothing() async {
        let expectedFilterSet = dataManager.filterSet
        let expectedHashPrefixes = dataManager.hashPrefixes

        // Save revision and update the filter set and hash prefixes
        dataManager.saveRevision(3)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        XCTAssertEqual(dataManager.filterSet, expectedFilterSet, "Filter set should match the expected set after update.")
        XCTAssertEqual(dataManager.hashPrefixes, expectedHashPrefixes, "Hash prefixes should match the expected set after update.")
    }

    func testRevision4AddsAndDeletesData() async {
        let expectedFilterSet: Set<Filter> = [
            Filter(hash: "testhash2", regex: ".*test.*"),
            Filter(hash: "testhash1", regex: ".*example.*"),
            Filter(hash: "testhash5", regex: ".*test.*")
        ]
        let expectedHashPrefixes: Set<String> = [
            "a379a6f6",
            "dd00ee11",
            "cc00dd11",
            "bb00cc11"
        ]

        // Save revision and update the filter set and hash prefixes
        dataManager.saveRevision(4)
        await updateManager.updateFilterSet()
        await updateManager.updateHashPrefixes()

        XCTAssertEqual(dataManager.filterSet, expectedFilterSet, "Filter set should match the expected set after update.")
        XCTAssertEqual(dataManager.hashPrefixes, expectedHashPrefixes, "Hash prefixes should match the expected set after update.")
    }
}
