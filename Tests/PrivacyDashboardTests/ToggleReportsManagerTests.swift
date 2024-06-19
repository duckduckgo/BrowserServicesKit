//
//  ToggleReportsManagerTests.swift
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

@testable import PrivacyDashboard
import XCTest

final class MockToggleReportsStore: ToggleReportsStoring {

    var dismissedAt: Date?
    var appearanceWindowStart: Date?
    var appearanceCount: Int = 0

}

final class ToggleReportsManagerTests: XCTestCase {

    // MARK: - Dismissal logic

    func testShouldShowToggleReportWhenNoDismissedDate() {
        let manager = ToggleReportsManager(store: MockToggleReportsStore())
        XCTAssertTrue(manager.shouldShowToggleReport)
    }

    func testRecordDismissal() {
        let store = MockToggleReportsStore()
        var manager = ToggleReportsManager(store: store)

        let now = Date()
        manager.recordDismissal(date: now)
        XCTAssertEqual(store.dismissedAt, now)
    }

    func testShouldShowToggleReportWhenDismissedDateIsMoreThan48HoursAgo() {
        let store = MockToggleReportsStore()
        let manager = ToggleReportsManager(store: store)
        let pastDate = Date(timeIntervalSinceNow: -49 * 60 * 60) // 49 hours ago
        store.dismissedAt = pastDate

        XCTAssertTrue(manager.shouldShowToggleReport(date: Date(), minimumDismissalInterval: 48 * 60 * 60))
    }

    func testShouldNotShowToggleReportWhenDismissedDateIsLessThan48HoursAgo() {
        let store = MockToggleReportsStore()
        let manager = ToggleReportsManager(store: store)
        let recentDate = Date(timeIntervalSinceNow: -47 * 60 * 60) // 47 hours ago
        store.dismissedAt = recentDate

        XCTAssertFalse(manager.shouldShowToggleReport(date: Date(), minimumDismissalInterval: 48 * 60 * 60))
    }

    // MARK: - Appearance logic

    func testShouldShowToggleReportWhenAppearanceLimitNotReached() {
        let store = MockToggleReportsStore()
        store.appearanceCount = 2
        let manager = ToggleReportsManager(store: store)

        XCTAssertTrue(manager.shouldShowToggleReport)
    }

    func testShouldNotShowToggleReportWhenAppearanceLimitReached() {
        let store = MockToggleReportsStore()
        store.appearanceCount = 3
        let manager = ToggleReportsManager(store: store)

        XCTAssertFalse(manager.shouldShowToggleReport)
    }

    // MARK: - Rolling window

    func testRecordAppearanceWhenWithinWindowShouldIncrementCount() {
        let store = MockToggleReportsStore()
        // Set initial window start within the last 48 hours
        let windowStart = Date().addingTimeInterval(-24 * 60 * 60)
        store.appearanceWindowStart = windowStart
        store.appearanceCount = 1
        
        var manager = ToggleReportsManager(store: store)
        // Record another appearance within the same window
        manager.recordAppearance(date: Date())

        XCTAssertEqual(store.appearanceCount, 2)
        XCTAssertEqual(store.appearanceWindowStart, windowStart)
    }

    func testRecordAppearanceWhenOutsideWindowShouldResetCount() {
        let store = MockToggleReportsStore()
        // Set initial window start more than 48 hours ago
        store.appearanceWindowStart = Date().addingTimeInterval(-72 * 60 * 60)
        store.appearanceCount = 2

        var manager = ToggleReportsManager(store: store)
        // Record appearance outside the previous window
        let now = Date()
        manager.recordAppearance(date: now)

        XCTAssertEqual(store.appearanceCount, 1)
        XCTAssertNotNil(store.appearanceWindowStart)
        XCTAssertEqual(store.appearanceWindowStart, now)
    }

    func testRecordAppearanceWhenNoWindowShouldStartNewWindow() {
        let store = MockToggleReportsStore()
        // No initial window start
        store.appearanceWindowStart = nil
        store.appearanceCount = 0

        var manager = ToggleReportsManager(store: store)
        // Record appearance without previous window
        let now = Date()
        manager.recordAppearance(date: now)

        XCTAssertEqual(store.appearanceCount, 1)
        XCTAssertNotNil(store.appearanceWindowStart)
        XCTAssertEqual(store.appearanceWindowStart, now)
    }

    // MARK: - Combination of both appearances and dismissal logic

    func testShouldNotShowToggleReportWhenDismissedLessThan48HoursAndAppearanceLimitNotReached() {
        let store = MockToggleReportsStore()
        store.dismissedAt = Date().addingTimeInterval(-24 * 60 * 60)
        store.appearanceCount = 2
        let manager = ToggleReportsManager(store: store)

        XCTAssertFalse(manager.shouldShowToggleReport(date: Date()))
    }

    func testShouldNotShowToggleReportWhenDismissedLessThan48HoursAndAppearanceLimitReached() {
        let store = MockToggleReportsStore()
        store.dismissedAt = Date().addingTimeInterval(-24 * 60 * 60)
        store.appearanceCount = 3
        let manager = ToggleReportsManager(store: store)

        XCTAssertFalse(manager.shouldShowToggleReport(date: Date()))
    }

    func testShouldNotShowToggleReportWhenDismissedMoreThan48HoursAndAppearanceLimitReached() {
        let store = MockToggleReportsStore()
        store.dismissedAt = Date().addingTimeInterval(-72 * 60 * 60)
        store.appearanceCount = 3
        let manager = ToggleReportsManager(store: store)

        XCTAssertFalse(manager.shouldShowToggleReport(date: Date()))
    }

    func testShouldShowToggleReportWhenDismissedMoreThan48HoursAndAppearanceLimitNotReached() {
        let store = MockToggleReportsStore()
        store.dismissedAt = Date().addingTimeInterval(-72 * 60 * 60)
        store.appearanceCount = 2
        let manager = ToggleReportsManager(store: store)

        XCTAssertTrue(manager.shouldShowToggleReport(date: Date()))
    }

}
