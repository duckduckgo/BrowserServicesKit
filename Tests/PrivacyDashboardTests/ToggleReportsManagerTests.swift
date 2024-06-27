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

final class MockToggleReportsFeature: ToggleReporting {

    var isEnabled: Bool = true
    var isDismissLogicEnabled: Bool = true
    var dismissInterval: TimeInterval = 60 * 60 * 48
    var isPromptLimitLogicEnabled: Bool = true
    var promptInterval: TimeInterval = 60 * 60 * 48
    var maxPromptCount: Int = 3

}

final class MockToggleReportsStore: ToggleReportsStoring {

    var dismissedAt: Date?
    var promptWindowStart: Date?
    var promptCount: Int = 0

}

final class ToggleReportsManagerTests: XCTestCase {

    // MARK: - Dismissal logic

    func testShouldShowToggleReportWhenNoDismissedDate() {
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: MockToggleReportsStore())
        XCTAssertTrue(manager.shouldShowToggleReport)
    }

    func testRecordDismissal() {
        let store = MockToggleReportsStore()
        var manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)

        let now = Date()
        manager.recordDismissal(date: now)
        XCTAssertEqual(store.dismissedAt, now)
    }

    func testShouldShowToggleReportWhenDismissedDateIsMoreThan48HoursAgo() {
        let store = MockToggleReportsStore()
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)
        let pastDate = Date(timeIntervalSinceNow: -49 * 60 * 60) // 49 hours ago
        store.dismissedAt = pastDate

        XCTAssertTrue(manager.shouldShowToggleReport(date: Date()))
    }

    func testShouldNotShowToggleReportWhenDismissedDateIsLessThan48HoursAgo() {
        let store = MockToggleReportsStore()
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)
        let recentDate = Date(timeIntervalSinceNow: -47 * 60 * 60) // 47 hours ago
        store.dismissedAt = recentDate

        XCTAssertFalse(manager.shouldShowToggleReport(date: Date()))
    }

    // MARK: - Prompt logic

    func testShouldShowToggleReportWhenPromptLimitNotReached() {
        let store = MockToggleReportsStore()
        store.promptCount = 2
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)

        XCTAssertTrue(manager.shouldShowToggleReport)
    }

    func testShouldNotShowToggleReportWhenPromptLimitReachedAndPromptIntervalIsLessThan48HoursAgo() {
        let store = MockToggleReportsStore()
        store.promptCount = 3
        store.promptWindowStart = Date().addingTimeInterval(-24 * 60 * 60)
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)

        XCTAssertFalse(manager.shouldShowToggleReport)
    }

    func testShouldShowToggleReportWhenPromptLimitReachedButPromptIntervalIsMoreThan48HoursAgo() {
        let store = MockToggleReportsStore()
        store.promptCount = 3
        store.promptWindowStart = Date().addingTimeInterval(-72 * 60 * 60)
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)

        XCTAssertTrue(manager.shouldShowToggleReport)
    }

    // MARK: - Rolling window

    func testRecordPromptWhenWithinWindowShouldIncrementCount() {
        let store = MockToggleReportsStore()
        // Set initial window start within the last 48 hours
        let windowStart = Date().addingTimeInterval(-24 * 60 * 60)
        store.promptWindowStart = windowStart
        store.promptCount = 1
        
        var manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)
        // Record another prompt within the same window
        manager.recordPrompt(date: Date())

        XCTAssertEqual(store.promptCount, 2)
        XCTAssertEqual(store.promptWindowStart, windowStart)
    }

    func testRecordPromptWhenOutsideWindowShouldResetCount() {
        let store = MockToggleReportsStore()
        // Set initial window start more than 48 hours ago
        store.promptWindowStart = Date().addingTimeInterval(-72 * 60 * 60)
        store.promptCount = 2

        var manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)
        // Record prompt outside the previous window
        let now = Date()
        manager.recordPrompt(date: now)

        XCTAssertEqual(store.promptCount, 1)
        XCTAssertNotNil(store.promptWindowStart)
        XCTAssertEqual(store.promptWindowStart, now)
    }

    func testRecordPromptWhenNoWindowShouldStartNewWindow() {
        let store = MockToggleReportsStore()
        // No initial window start
        store.promptWindowStart = nil
        store.promptCount = 0

        var manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)
        // Record prompt without previous window
        let now = Date()
        manager.recordPrompt(date: now)

        XCTAssertEqual(store.promptCount, 1)
        XCTAssertNotNil(store.promptWindowStart)
        XCTAssertEqual(store.promptWindowStart, now)
    }

    // MARK: - Combination of both prompts and dismissal logic

    func testShouldNotShowToggleReportWhenDismissedLessThan48HoursAndPromptLimitNotReached() {
        let store = MockToggleReportsStore()
        store.dismissedAt = Date().addingTimeInterval(-24 * 60 * 60)
        store.promptCount = 2
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)

        XCTAssertFalse(manager.shouldShowToggleReport(date: Date()))
    }

    func testShouldNotShowToggleReportWhenDismissedLessThan48HoursAndPromptLimitReached() {
        let store = MockToggleReportsStore()
        store.dismissedAt = Date().addingTimeInterval(-24 * 60 * 60)
        store.promptCount = 3
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)

        XCTAssertFalse(manager.shouldShowToggleReport(date: Date()))
    }

    func testShouldNotShowToggleReportWhenDismissedMoreThan48HoursAndPromptLimitReached() {
        let store = MockToggleReportsStore()
        store.dismissedAt = Date().addingTimeInterval(-72 * 60 * 60)
        store.promptWindowStart = Date().addingTimeInterval(-24 * 60 * 60)
        store.promptCount = 3
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)

        XCTAssertFalse(manager.shouldShowToggleReport(date: Date()))
    }

    func testShouldShowToggleReportWhenDismissedMoreThan48HoursAndPromptLimitNotReached() {
        let store = MockToggleReportsStore()
        store.dismissedAt = Date().addingTimeInterval(-72 * 60 * 60)
        store.promptCount = 2
        let manager = ToggleReportsManager(feature: MockToggleReportsFeature(), store: store)

        XCTAssertTrue(manager.shouldShowToggleReport(date: Date()))
    }

    // MARK: - Feature

    func testShouldNotShowToggleReportWhenFeatureDisabled() {
        let feature = MockToggleReportsFeature()
        feature.isEnabled = false
        let manager = ToggleReportsManager(feature: feature, store: MockToggleReportsStore())
        XCTAssertFalse(manager.shouldShowToggleReport)
    }

    func testShouldShowToggleReportWhenPromptLimitReachedButPromptLimitLogicDisabled() {
        let store = MockToggleReportsStore()
        store.promptWindowStart = Date().addingTimeInterval(-24 * 60 * 60)
        store.promptCount = 5
        let feature = MockToggleReportsFeature()
        let manager = ToggleReportsManager(feature: feature, store: store)
        XCTAssertFalse(manager.shouldShowToggleReport)
        feature.isPromptLimitLogicEnabled = false
        XCTAssertTrue(manager.shouldShowToggleReport)
    }

    func testShouldShowToggleReportWhenDismissedDateIsLessThan48HoursAgoButDismissLogicDisabled() {
        let store = MockToggleReportsStore()
        store.dismissedAt = Date().addingTimeInterval(-47 * 60 * 60)
        let feature = MockToggleReportsFeature()
        let manager = ToggleReportsManager(feature: feature, store: store)
        XCTAssertFalse(manager.shouldShowToggleReport)
        feature.isDismissLogicEnabled = false
        XCTAssertTrue(manager.shouldShowToggleReport)
    }

}
