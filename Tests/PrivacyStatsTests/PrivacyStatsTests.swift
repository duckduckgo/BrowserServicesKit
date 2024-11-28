//
//  PrivacyStatsTests.swift
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

import Combine
import Persistence
import TrackerRadarKit
import XCTest
@testable import PrivacyStats

final class TestPrivacyStatsDatabaseProvider: PrivacyStatsDatabaseProviding {
    let databaseName: String
    var database: CoreDataDatabase!
    var location: URL!

    init(databaseName: String) {
        self.databaseName = databaseName
    }

    func initializeDatabase() -> CoreDataDatabase {
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CoreDataDatabase.loadModel(from: PrivacyStats.bundle, named: "PrivacyStats")!
        database = CoreDataDatabase(name: databaseName, containerLocation: location, model: model)
        database.loadStore()
        return database
    }

    func tearDownDatabase() {
        try? database.tearDown(deleteStores: true)
        database = nil
        try? FileManager.default.removeItem(at: location)
    }
}

final class PrivacyStatsTests: XCTestCase {
    var databaseProvider: TestPrivacyStatsDatabaseProvider!
    var privacyStats: PrivacyStats!

    override func setUp() async throws {
        databaseProvider = TestPrivacyStatsDatabaseProvider(databaseName: type(of: self).description())
        privacyStats = PrivacyStats(databaseProvider: databaseProvider)
    }

    // MARK: - fetchPrivacyStats

    func testThatPrivacyStatsAreFetched() async throws {
        let stats = await privacyStats.fetchPrivacyStats()
        XCTAssertEqual(stats, [:])
    }

    func testThatFetchPrivacyStatsReturnsAllCompanies() async throws {
        try addObjects { context in
            [
                DailyBlockedTrackersEntity.make(companyName: "A", count: 10, context: context),
                DailyBlockedTrackersEntity.make(companyName: "B", count: 5, context: context),
                DailyBlockedTrackersEntity.make(companyName: "C", count: 13, context: context),
                DailyBlockedTrackersEntity.make(companyName: "D", count: 42, context: context)
            ]
        }

        let stats = await privacyStats.fetchPrivacyStats()
        XCTAssertEqual(stats, ["A": 10, "B": 5, "C": 13, "D": 42])
    }

    func testThatFetchPrivacyStatsReturnsSumOfCompanyEntriesForPast7Days() async throws {
        try addObjects { context in
            let date = Date()

            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 1, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(1), companyName: "A", count: 2, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(2), companyName: "A", count: 3, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(3), companyName: "A", count: 4, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(4), companyName: "A", count: 5, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(5), companyName: "A", count: 6, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(6), companyName: "A", count: 7, context: context)
            ]
        }

        let stats = await privacyStats.fetchPrivacyStats()
        XCTAssertEqual(stats, ["A": 28])
    }

    func testThatFetchPrivacyStatsDiscardsEntriesOlderThan7Days() async throws {
        try addObjects { context in
            let date = Date()

            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 1, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(1), companyName: "A", count: 2, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(7), companyName: "A", count: 10, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(10), companyName: "A", count: 10, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(20), companyName: "A", count: 10, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(500), companyName: "A", count: 10, context: context),
            ]
        }

        let stats = await privacyStats.fetchPrivacyStats()
        XCTAssertEqual(stats, ["A": 3])
    }

    // MARK: - recordBlockedTracker

    func testThatCallingRecordBlockedTrackerCausesDatabaseSaveAfterDelay() async throws {
        await privacyStats.recordBlockedTracker("A")

        var stats = await privacyStats.fetchPrivacyStats()
        XCTAssertEqual(stats, [:])

        try await Task.sleep(nanoseconds: 1_100_000_000)

        stats = await privacyStats.fetchPrivacyStats()
        XCTAssertEqual(stats, ["A": 1])
    }

    func testThatStatsUpdatePublisherIsCalledAfterDatabaseSave() async throws {
        await privacyStats.recordBlockedTracker("A")

        await waitForStatsUpdateEvent()

        var stats = await privacyStats.fetchPrivacyStats()
        XCTAssertEqual(stats, ["A": 1])

        await privacyStats.recordBlockedTracker("B")

        await waitForStatsUpdateEvent()

        stats = await privacyStats.fetchPrivacyStats()
        XCTAssertEqual(stats, ["A": 1, "B": 1])
    }

    func testWhenMultipleTrackersAreReportedInQuickSuccessionThenOnlyOneStatsUpdateEventIsReported() async throws {
        await withTaskGroup(of: Void.self) { group in
            (0..<5).forEach { _ in
                group.addTask {
                    await self.privacyStats.recordBlockedTracker("A")
                }
            }
            (0..<10).forEach { _ in
                group.addTask {
                    await self.privacyStats.recordBlockedTracker("B")
                }
            }
            (0..<3).forEach { _ in
                group.addTask {
                    await self.privacyStats.recordBlockedTracker("C")
                }
            }
        }

        // We have limited testing possibilities here, so let's just await the first stats update event
        // and verify that all trackers are reported by privacy stats.
        await waitForStatsUpdateEvent()

        let stats = await privacyStats.fetchPrivacyStats()
        XCTAssertEqual(stats, ["A": 5, "B": 10, "C": 3])
    }

    // MARK: - clearPrivacyStats

    func testWhenClearPrivacyStatsIsCalledThenFetchPrivacyStatsIsEmpty() async throws {
        try addObjects { context in
            let date = Date()

            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 1, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(1), companyName: "A", count: 2, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(7), companyName: "A", count: 10, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(10), companyName: "A", count: 10, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(20), companyName: "A", count: 10, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(500), companyName: "A", count: 10, context: context),
            ]
        }

        var stats = await privacyStats.fetchPrivacyStats()
        XCTAssertFalse(stats.isEmpty)

        await privacyStats.clearPrivacyStats()

        stats = await privacyStats.fetchPrivacyStats()
        XCTAssertTrue(stats.isEmpty)

        let context = databaseProvider.database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            do {
                let allObjects = try context.fetch(DailyBlockedTrackersEntity.fetchRequest())
                XCTAssertTrue(allObjects.isEmpty)
            } catch {
                XCTFail("fetch failed: \(error)")
            }
        }
    }

    // MARK: - Helpers

    func waitForStatsUpdateEvent(file: StaticString = #file, line: UInt = #line) async {
        let expectation = self.expectation(description: "statsUpdate")
        let cancellable = privacyStats.statsUpdatePublisher.sink { expectation.fulfill() }
        await fulfillment(of: [expectation])
        cancellable.cancel()
    }

    func addObjects(_ objects: (NSManagedObjectContext) -> [DailyBlockedTrackersEntity], file: StaticString = #file, line: UInt = #line) throws {
        let context = databaseProvider.database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            _ = objects(context)
            do {
                try context.save()
            } catch {
                XCTFail("save failed: \(error)", file: file, line: line)
            }
        }
    }
}
