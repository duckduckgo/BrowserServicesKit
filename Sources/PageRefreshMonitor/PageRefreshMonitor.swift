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

    static let pageRefreshMonitorDidDetectRefreshPattern = Notification.Name("com.duckduckgo.app.pageRefreshMonitorDidDetectRefreshPattern")

}

public protocol PageRefreshStoring {

    var refreshTimestamps: [Date] { get set }

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

/// Monitors page refresh events for a specific URL without storing URLs or any personally identifiable information.
///
/// Triggers `onDidDetectRefreshPattern` and posts a `pageRefreshMonitorDidDetectRefreshPattern` notification
/// if three refreshes occur within a 20-second window.
public final class PageRefreshMonitor: PageRefreshMonitoring {

    public typealias NumberOfRefreshes = Int
    private let onDidDetectRefreshPattern: (_ numberOfRefreshes: NumberOfRefreshes) -> Void
    private var store: PageRefreshStoring
    private var lastRefreshedURL: URL?

    public init(onDidDetectRefreshPattern: @escaping (NumberOfRefreshes) -> Void,
                store: PageRefreshStoring) {
        self.onDidDetectRefreshPattern = onDidDetectRefreshPattern
        self.store = store
    }

    var refreshTimestamps: [Date] {
        get { store.refreshTimestamps }
        set { store.refreshTimestamps = newValue }
    }

    public func register(for url: URL, date: Date = Date()) {
        resetIfURLChanged(to: url)

        // Add the new refresh timestamp
        refreshTimestamps.append(date)

        let refreshesInLast20Secs = refreshTimestamps.filter { date.timeIntervalSince($0) < 20.0 }
        let refreshesInLast12Secs = refreshTimestamps.filter { date.timeIntervalSince($0) < 12.0 }

        // Trigger detection if two refreshes occurred within 12 seconds
        if refreshesInLast12Secs.count > 1 {
            onDidDetectRefreshPattern(2)
        }
        // Trigger detection if three refreshes occurred within 20 seconds
        if refreshesInLast20Secs.count > 2 {
            onDidDetectRefreshPattern(3)
            NotificationCenter.default.post(name: .pageRefreshMonitorDidDetectRefreshPattern, object: self)
            refreshTimestamps.removeAll() // Reset timestamps after detection
        }
    }

    private func resetIfURLChanged(to newURL: URL) {
        if lastRefreshedURL != newURL {
            refreshTimestamps.removeAll()
            lastRefreshedURL = newURL
        }
    }

}
