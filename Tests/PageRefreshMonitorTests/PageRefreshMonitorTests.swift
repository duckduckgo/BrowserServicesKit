//
//  PageRefreshMonitorTests.swift
//  DuckDuckGo
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

import XCTest
import Common
@testable import PageRefreshMonitor

final class MockPageRefreshEventsMapping: EventMapping<PageRefreshEvent> {

    init(captureEvent: @escaping (PageRefreshEvent) -> Void) {
        super.init { event, _, _, _ in
            captureEvent(event)
        }
    }

    override init(mapping: @escaping EventMapping<PageRefreshEvent>.Mapping) {
        fatalError("Use init()")
    }
}

final class MockPageRefreshStore: PageRefreshStoring {

    var didRefreshTimestamp: Date?
    var didDoubleRefreshTimestamp: Date?
    var didRefreshCounter: Int = 0

}

final class PageRefreshMonitorTests: XCTestCase {

    var eventMapping: MockPageRefreshEventsMapping!
    var monitor: PageRefreshMonitor!
    var events: [PageRefreshEvent] = []

    override func setUp() {
        super.setUp()
        events.removeAll()
        eventMapping = MockPageRefreshEventsMapping(captureEvent: { event in
            self.events.append(event)
        })
        monitor = PageRefreshMonitor(eventMapping: eventMapping,
                                     store: MockPageRefreshStore())
    }

    // - MARK: Behavior testing
    // Expecting events

    func testWhenUserRefreshesTwiceOnSameURLItSendsReloadTwiceEvent() {
        let url = URL(string: "https://example.com/pageA")!
        monitor.handleRefreshAction(for: url)
        monitor.handleRefreshAction(for: url)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .twiceWithin12Seconds)
    }

    func testWhenUserRefreshesThreeTimesOnSameURLItSendsTwoReloadTwiceEvents() {
        let url = URL(string: "https://example.com/pageA")!
        monitor.handleRefreshAction(for: url)
        monitor.handleRefreshAction(for: url)
        monitor.handleRefreshAction(for: url)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .twiceWithin12Seconds)
        XCTAssertEqual(events[1], .twiceWithin12Seconds)
    }

    func testWhenUserRefreshesThreeTimesOnSameURLItSendsReloadThreeTimesEvent() {
        let url = URL(string: "https://example.com/pageA")!
        monitor.handleRefreshAction(for: url)
        monitor.handleRefreshAction(for: url)
        monitor.handleRefreshAction(for: url)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[2], .threeTimesWithin20Seconds)
    }

    // URL change

    func testWhenUserRefreshesOnDifferentURLItResetsCounterSoNoEventIsBeingSent() {
        let urlA = URL(string: "https://example.com/pageA")!
        let urlB = URL(string: "https://example.com/pageB")!
        monitor.handleRefreshAction(for: urlA)
        monitor.handleRefreshAction(for: urlB)
        XCTAssertTrue(events.isEmpty)
    }

    func testWhenUserRefreshesOnDifferentURLItResetsCounterAndStartsTheNewCounterForNewPage() {
        let urlA = URL(string: "https://example.com/pageA")!
        let urlB = URL(string: "https://example.com/pageB")!
        monitor.handleRefreshAction(for: urlA)
        monitor.handleRefreshAction(for: urlB)
        monitor.handleRefreshAction(for: urlB)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .twiceWithin12Seconds)
    }

    // Timed pixels

    func testReloadTwiceEventShouldNotSendEventIfSecondRefreshOnSameURLOccurredAfter12Seconds() {
        let url = URL(string: "https://example.com/pageA")!
        let date = Date()
        monitor.handleRefreshAction(for: url, date: date)
        monitor.handleRefreshAction(for: url, date: date + 13) // 13 seconds after the first event
        XCTAssertTrue(events.isEmpty)
    }

    func testReloadTwiceEventShouldSendEventIfSecondRefreshOnSameURLOccurredBelow12Seconds() {
        let url = URL(string: "https://example.com/pageA")!
        let date = Date()
        monitor.handleRefreshAction(for: url, date: date)
        monitor.handleRefreshAction(for: url, date: date + 11) // 11 seconds after the first event
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .twiceWithin12Seconds)
    }

    func testReloadThreeTimesEventShouldNotSendEventIfThreeRefreshesOnSameURLOccurredAfter20Seconds() {
        let url = URL(string: "https://example.com/pageA")!
        let date = Date()
        monitor.handleRefreshAction(for: url, date: date)
        monitor.handleRefreshAction(for: url, date: date)
        monitor.handleRefreshAction(for: url, date: date + 21) // 21 seconds after the first event
        events.removeAll { $0 == .twiceWithin12Seconds } // remove events that are not being tested
        XCTAssertTrue(events.isEmpty)
    }

    func testReloadThreeTimesEventShouldSendEventIfThreeRefreshesOnSameURLOccurredBelow20Seconds() {
        let url = URL(string: "https://example.com/pageA")!
        let date = Date()
        monitor.handleRefreshAction(for: url, date: date)
        monitor.handleRefreshAction(for: url, date: date)
        monitor.handleRefreshAction(for: url, date: date + 19) // 19 seconds after the first event
        events.removeAll { $0 == .twiceWithin12Seconds } // remove events that are not being tested
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], .threeTimesWithin20Seconds)
    }

}
