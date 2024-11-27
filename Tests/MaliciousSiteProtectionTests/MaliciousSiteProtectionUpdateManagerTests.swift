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

import Clocks
import Common
import Foundation
import XCTest

@testable import MaliciousSiteProtection

class MaliciousSiteProtectionUpdateManagerTests: XCTestCase {

    var updateManager: MaliciousSiteProtection.UpdateManager!
    var dataManager: MockMaliciousSiteProtectionDataManager!
    var apiClient: MockMaliciousSiteProtectionAPIClient!
    var updateIntervalProvider: UpdateManager.UpdateIntervalProvider!
    var clock: TestClock<Duration>!
    var willSleep: ((TimeInterval) -> Void)?
    var updateTask: Task<Void, Error>?

    override func setUp() async throws {
        apiClient = MockMaliciousSiteProtectionAPIClient()
        dataManager = MockMaliciousSiteProtectionDataManager()
        clock = TestClock()

        let clockSleeper = Sleeper(clock: clock)
        let reportingSleeper = Sleeper {
            self.willSleep?($0)
            try await clockSleeper.sleep(for: $0)
        }

        updateManager = MaliciousSiteProtection.UpdateManager(apiClient: apiClient, dataManager: dataManager, sleeper: reportingSleeper, updateIntervalProvider: { self.updateIntervalProvider($0) })
    }

    override func tearDown() async throws {
        updateManager = nil
        dataManager = nil
        apiClient = nil
        updateIntervalProvider = nil
        updateTask?.cancel()
    }

    func testUpdateHashPrefixes() async {
        await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))
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
        await updateManager.updateData(for: .filterSet(threatKind: .phishing))
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
        await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

        // revision 1 -> 2
        await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

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

        await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

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

        await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

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

        await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

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

        await updateManager.updateData(for: .filterSet(threatKind: .phishing))
        await updateManager.updateData(for: .hashPrefixes(threatKind: .phishing))

        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))

        XCTAssertEqual(hashPrefixes, HashPrefixSet(revision: 6, items: expectedHashPrefixes), "Hash prefixes should match the expected set after update.")
        XCTAssertEqual(filterSet, FilterDictionary(revision: 6, items: expectedFilterSet), "Filter set should match the expected set after update.")
    }

    func testWhenPeriodicUpdatesStart_dataSetsAreUpdated() async throws {
        self.updateIntervalProvider = { _ in 1 }

        let eHashPrefixesUpdated = expectation(description: "Hash prefixes updated")
        let c1 = await dataManager.publisher(for: .hashPrefixes(threatKind: .phishing)).dropFirst().sink { data in
            eHashPrefixesUpdated.fulfill()
        }
        let eFilterSetUpdated = expectation(description: "Filter set updated")
        let c2 = await dataManager.publisher(for: .filterSet(threatKind: .phishing)).dropFirst().sink { data in
            eFilterSetUpdated.fulfill()
        }

        updateTask = updateManager.startPeriodicUpdates()
        await Task.megaYield(count: 10)

        // expect initial update run instantly
        await fulfillment(of: [eHashPrefixesUpdated, eFilterSetUpdated], timeout: 1)

        withExtendedLifetime((c1, c2)) {}
    }

    func testWhenPeriodicUpdatesAreEnabled_dataSetsAreUpdatedContinuously() async throws {
        // Start periodic updates
        self.updateIntervalProvider = { dataType in
            switch dataType {
            case .filterSet: return 2
            case .hashPrefixSet: return 1
            }
        }

        let hashPrefixUpdateExpectations = [
            XCTestExpectation(description: "Hash prefixes rev.1 update received"),
            XCTestExpectation(description: "Hash prefixes rev.2 update received"),
            XCTestExpectation(description: "Hash prefixes rev.3 update received"),
        ]
        let filterSetUpdateExpectations = [
            XCTestExpectation(description: "Filter set rev.1 update received"),
            XCTestExpectation(description: "Filter set rev.2 update received"),
            XCTestExpectation(description: "Filter set rev.3 update received"),
        ]
        let hashPrefixSleepExpectations = [
            XCTestExpectation(description: "HP Will Sleep 1"),
            XCTestExpectation(description: "HP Will Sleep 2"),
            XCTestExpectation(description: "HP Will Sleep 3"),
        ]
        let filterSetSleepExpectations = [
            XCTestExpectation(description: "FS Will Sleep 1"),
            XCTestExpectation(description: "FS Will Sleep 2"),
            XCTestExpectation(description: "FS Will Sleep 3"),
        ]

        let c1 = await dataManager.publisher(for: .hashPrefixes(threatKind: .phishing)).dropFirst().sink { data in
            hashPrefixUpdateExpectations[data.revision - 1].fulfill()
        }
        let c2 = await dataManager.publisher(for: .filterSet(threatKind: .phishing)).dropFirst().sink { data in
            filterSetUpdateExpectations[data.revision - 1].fulfill()
        }
        var hashPrefixSleepIndex = 0
        var filterSetSleepIndex = 0
        self.willSleep = { interval in
            if interval == 1 {
                hashPrefixSleepExpectations[safe: hashPrefixSleepIndex]?.fulfill()
                hashPrefixSleepIndex += 1
            } else {
                filterSetSleepExpectations[safe: filterSetSleepIndex]?.fulfill()
                filterSetSleepIndex += 1
            }
        }

        // expect initial hashPrefixes update run instantly
        updateTask = updateManager.startPeriodicUpdates()
        await fulfillment(of: [hashPrefixUpdateExpectations[0], hashPrefixSleepExpectations[0], filterSetUpdateExpectations[0], filterSetSleepExpectations[0]], timeout: 1)

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(1))
        // expect to receive v.2 update for hashPrefixes
        await fulfillment(of: [hashPrefixUpdateExpectations[1], hashPrefixSleepExpectations[1]], timeout: 1)

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(1))
        // expect to receive v.3 update for hashPrefixes and v.2 update for filterSet
        await fulfillment(of: [hashPrefixUpdateExpectations[2], hashPrefixSleepExpectations[2], filterSetUpdateExpectations[1], filterSetSleepExpectations[1]], timeout: 1)        //

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(2))
        // expect to receive v.3 update for filterSet and no update for hashPrefixes (no v.3 updates in the mock)
        await fulfillment(of: [filterSetUpdateExpectations[2], filterSetSleepExpectations[2]], timeout: 1)        //

        withExtendedLifetime((c1, c2)) {}
    }

    func testWhenPeriodicUpdatesAreDisabled_noDataSetsAreUpdated() async throws {
        // Start periodic updates
        self.updateIntervalProvider = { dataType in
            switch dataType {
            case .filterSet: return nil // Set update interval to nil for FilterSet
            case .hashPrefixSet: return 1
            }
        }

        let expectations = [
            XCTestExpectation(description: "Hash prefixes rev.1 update received"),
            XCTestExpectation(description: "Hash prefixes rev.2 update received"),
            XCTestExpectation(description: "Hash prefixes rev.3 update received"),
        ]
        let c1 = await dataManager.publisher(for: .hashPrefixes(threatKind: .phishing)).dropFirst().sink { data in
            expectations[data.revision - 1].fulfill()
        }
        // data for FilterSet should not be updated
        let c2 = await dataManager.publisher(for: .filterSet(threatKind: .phishing)).dropFirst().sink { data in
            XCTFail("Unexpected filter set update received: \(data)")
        }
        // synchronize Task threads to advance the Test Clock when the updated Task is sleeping,
        // otherwise we‘ll eventually advance the clock before the sleep and get hung.
        var sleepIndex = 0
        let sleepExpectations = [
            XCTestExpectation(description: "Will Sleep 1"),
            XCTestExpectation(description: "Will Sleep 2"),
            XCTestExpectation(description: "Will Sleep 3"),
        ]
        self.willSleep = { _ in
            sleepExpectations[sleepIndex].fulfill()
            sleepIndex += 1
        }

        // expect initial hashPrefixes update run instantly
        updateTask = updateManager.startPeriodicUpdates()
        await fulfillment(of: [expectations[0], sleepExpectations[0]], timeout: 1)

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(1))
        // expect to receive v.2 update for hashPrefixes
        await fulfillment(of: [expectations[1], sleepExpectations[1]], timeout: 1)

        // Advance the clock by 1 seconds
        await self.clock.advance(by: .seconds(1))
        // expect to receive v.3 update for hashPrefixes
        await fulfillment(of: [expectations[2], sleepExpectations[2]], timeout: 1)

        withExtendedLifetime((c1, c2)) {}
    }

    func testWhenPeriodicUpdatesAreCancelled_noFurtherUpdatesReceived() async throws {
        // Start periodic updates
        self.updateIntervalProvider = { _ in 1 }
        updateTask = updateManager.startPeriodicUpdates()

        // Wait for the initial update
        try await withTimeout(1) { [self] in
            for await _ in await dataManager.publisher(for: .filterSet(threatKind: .phishing)).first(where: { $0.revision == 1 }).values {}
            for await _ in await dataManager.publisher(for: .filterSet(threatKind: .phishing)).first(where: { $0.revision == 1 }).values {}
        }

        // Cancel the update task
        updateTask!.cancel()

        // Reset expectations for further updates
        let c = await dataManager.$store.dropFirst().sink { data in
            XCTFail("Unexpected data update received: \(data)")
        }

        // Advance the clock to check for further updates
        await self.clock.advance(by: .seconds(2))
        await clock.run()
        await Task.megaYield(count: 10)

        // Verify that the data sets have not been updated further
        let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: .phishing))
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: .phishing))
        XCTAssertEqual(hashPrefixes.revision, 1) // Expecting revision to remain 1
        XCTAssertEqual(filterSet.revision, 1) // Expecting revision to remain 1

        withExtendedLifetime(c) {}
    }

}