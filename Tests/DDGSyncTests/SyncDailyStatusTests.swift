//
//  SyncDailyStatusTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import XCTest
import TestUtils
@testable import DDGSync

class SyncDailyStatusTests: XCTestCase {

    static let featureA = Feature(name: "featureA")
    static let featureB = Feature(name: "featureB")

    static let error1 = SyncError.unexpectedStatusCode(400)
    static let error2 = SyncError.unexpectedStatusCode(413)

    let store = MockKeyValueStore()
    var status: SyncDailyStatus!

    var statusDict: [String: Int]? {
        store.object(forKey: SyncDailyStatus.Constants.dailyStatusDictKey) as? [String: Int]
    }

    override func setUp() {
        super.setUp()

        status = SyncDailyStatus(store: store)

        XCTAssertNil(store.object(forKey: SyncDailyStatus.Constants.lastSentDate))
        XCTAssertNil(store.object(forKey: SyncDailyStatus.Constants.syncCountParam))
    }

    func testWhenSyncIsFinishedThenCountIncreases() {
        status.onSyncFinished(with: nil)

        XCTAssertEqual(statusDict?[SyncDailyStatus.Constants.syncCountParam], 1)

        status.onSyncFinished(with: nil)

        XCTAssertEqual(statusDict?[SyncDailyStatus.Constants.syncCountParam], 2)
    }

    func testWhenErrorIsFoundThenCountsIncrease() {
        status.onSyncFinished(with: SyncOperationError(featureErrors: [.init(feature: Self.featureA,
                                                                             underlyingError: Self.error1)]))

        XCTAssertEqual(statusDict?[SyncDailyStatus.Constants.syncCountParam], 1)
        XCTAssertEqual(statusDict?[SyncDailyStatus.ErrorType(syncError: Self.error1)?.key(for: Self.featureA) ?? ""], 1)

        status.onSyncFinished(with: SyncOperationError(featureErrors: [.init(feature: Self.featureA,
                                                                             underlyingError: Self.error1),
                                                                       .init(feature: Self.featureB,
                                                                             underlyingError: Self.error2)]))

        XCTAssertEqual(statusDict?[SyncDailyStatus.Constants.syncCountParam], 2)
        XCTAssertEqual(statusDict?[SyncDailyStatus.ErrorType(syncError: Self.error1)?.key(for: Self.featureA) ?? ""], 2)
        XCTAssertEqual(statusDict?[SyncDailyStatus.ErrorType(syncError: Self.error2)?.key(for: Self.featureB) ?? ""], 1)
    }

    func testWhenNewInstallThenSendNothing() {

        status.sendStatusIfNeeded { _ in
            XCTFail("Should not execute")
        }

        XCTAssertNotNil(store.object(forKey: SyncDailyStatus.Constants.lastSentDate))
    }

    func testWhenSameDayThenSendNothing() {
        status.sendStatusIfNeeded { _ in
            XCTFail("Should not execute")
        }

        let firstStoredDate = store.object(forKey: SyncDailyStatus.Constants.lastSentDate) as? Date
        XCTAssertNotNil(firstStoredDate)

        Thread.sleep(forTimeInterval: 0.1)

        status.sendStatusIfNeeded { _ in
            XCTFail("Should not execute")
        }

        XCTAssertNotNil(store.object(forKey: SyncDailyStatus.Constants.lastSentDate))
        XCTAssertEqual(store.object(forKey: SyncDailyStatus.Constants.lastSentDate) as? Date, firstStoredDate)
    }

    func testWhenNextDayThenSendData() {
        let currentDate = Date()
        guard let yesterday = Calendar.current.date(byAdding: DateComponents(day: -1), to: currentDate) else {
            XCTFail("Could not create date")
            return
        }

        XCTAssertFalse(Calendar.current.isDate(currentDate, inSameDayAs: yesterday))
        XCTAssertFalse(Calendar.current.isDateInToday(yesterday))

        status.sendStatusIfNeeded(currentDate: yesterday)  { _ in
            XCTFail("Should not execute")
        }

        XCTAssertEqual(store.object(forKey: SyncDailyStatus.Constants.lastSentDate) as? Date, yesterday)

        let exp = expectation(description: "Should send data")

        status.onSyncFinished(with: nil)
        status.sendStatusIfNeeded(currentDate: currentDate) { data in
            XCTAssertEqual(data[SyncDailyStatus.Constants.syncCountParam], "1")
            exp.fulfill()
        }

        XCTAssertEqual(store.object(forKey: SyncDailyStatus.Constants.lastSentDate) as? Date, currentDate)

        wait(for: [exp], timeout: 1)
    }

    func testWhenNextDayButNoDataThenDontSendData() {
        let currentDate = Date()
        guard let yesterday = Calendar.current.date(byAdding: DateComponents(day: -1), to: currentDate) else {
            XCTFail("Could not create date")
            return
        }

        XCTAssertFalse(Calendar.current.isDate(currentDate, inSameDayAs: yesterday))
        XCTAssertFalse(Calendar.current.isDateInToday(yesterday))

        status.sendStatusIfNeeded(currentDate: yesterday)  { _ in
            XCTFail("Should not execute")
        }

        XCTAssertEqual(store.object(forKey: SyncDailyStatus.Constants.lastSentDate) as? Date, yesterday)

        status.sendStatusIfNeeded(currentDate: currentDate) { _ in
            XCTFail("Should not execute - no data")
        }

        XCTAssertEqual(store.object(forKey: SyncDailyStatus.Constants.lastSentDate) as? Date, currentDate)
    }

}
