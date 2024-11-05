//
//  PageRefreshMonitor.swift
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
import Common

public extension Notification.Name {

    static let pageRefreshDidMatchBrokenSiteCriteria = Notification.Name("com.duckduckgo.app.pageRefreshDidMatchBrokenSiteCriteria")

}

public enum PageRefreshEvent: String {

    public static let key = "com.duckduckgo.app.pageRefreshPattern.key"

    case twiceWithin12Seconds = "reload-twice-within-12-seconds"
    case threeTimesWithin20Seconds = "reload-three-times-within-20-seconds"

}

public protocol PageRefreshStoring {

    var didRefreshTimestamp: Date? { get set }
    var didDoubleRefreshTimestamp: Date? { get set }
    var didRefreshCounter: Int { get set }

}

public protocol PageRefreshMonitoring {

    func register(for url: URL, date: Date)
    func register(for url: URL)

}

public extension PageRefreshMonitoring {

    func register(for url: URL) {
        register(for: url, date: Date())
    }

}

public final class PageRefreshMonitor: PageRefreshMonitoring {

    enum Action: Equatable {

        case refresh

    }

    var lastRefreshedURL: URL?
    private let eventMapping: EventMapping<PageRefreshEvent>
    private var store: PageRefreshStoring

    public init(eventMapping: EventMapping<PageRefreshEvent>,
                store: PageRefreshStoring) {
        self.eventMapping = eventMapping
        self.store = store
    }

    var didRefreshTimestamp: Date? {
        get { store.didRefreshTimestamp }
        set { store.didRefreshTimestamp = newValue }
    }

    var didDoubleRefreshTimestamp: Date? {
        get { store.didDoubleRefreshTimestamp }
        set { store.didDoubleRefreshTimestamp = newValue }
    }

    var didRefreshCounter: Int {
        get { store.didRefreshCounter }
        set { store.didRefreshCounter = newValue }
    }

    public func register(for url: URL, date: Date = Date()) {
        resetIfURLChanged(to: url)
        fireEventIfActionOccurredRecently(within: 12.0, since: didRefreshTimestamp, eventToFire: .twiceWithin12Seconds)
        didRefreshTimestamp = date

        if didRefreshCounter == 0 {
            didDoubleRefreshTimestamp = date
        }
        didRefreshCounter += 1
        if didRefreshCounter > 2 {
            fireEventIfActionOccurredRecently(within: 20.0, since: didDoubleRefreshTimestamp, eventToFire: .threeTimesWithin20Seconds)
            didRefreshCounter = 0
        }

        func fireEventIfActionOccurredRecently(within interval: Double = 30.0, since timestamp: Date?, eventToFire: PageRefreshEvent) {
            if let timestamp = timestamp, date.timeIntervalSince(timestamp) < interval {
                eventMapping.fire(eventToFire)
                NotificationCenter.default.post(name: .pageRefreshDidMatchBrokenSiteCriteria,
                                                object: self,
                                                userInfo: [PageRefreshEvent.key: eventToFire])
            }
        }
    }

    private func resetIfURLChanged(to newURL: URL) {
        if lastRefreshedURL != newURL {
            didRefreshCounter = 0
            didRefreshTimestamp = nil
            didDoubleRefreshTimestamp = nil
            lastRefreshedURL = newURL
        }
    }

}
