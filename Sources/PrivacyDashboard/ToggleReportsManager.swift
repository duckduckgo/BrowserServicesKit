//
//  ToggleReportsManager.swift
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
import BrowserServicesKit

public protocol ToggleReportsStoring {

    var dismissedAt: Date? { get set }
    var promptWindowStart: Date? { get set }
    var promptCount: Int { get set }

}

public struct ToggleReportsStore: ToggleReportsStoring {

    private enum Key {

        static let dismissedAt = "com.duckduckgo.app.toggleReports.dismissedAt"
        static let promptWindowStart = "com.duckduckgo.app.toggleReports.promptWindowStart"
        static let promptCount = "com.duckduckgo.app.toggleReports.promptCount"

    }

    private let userDefaults = UserDefaults()
    public init() {}

    public var dismissedAt: Date? {
        get { userDefaults.object(forKey: Key.dismissedAt) as? Date }
        set { userDefaults.set(newValue, forKey: Key.dismissedAt) }
    }

    public var promptWindowStart: Date? {
        get { userDefaults.object(forKey: Key.promptWindowStart) as? Date }
        set { userDefaults.set(newValue, forKey: Key.promptWindowStart) }
    }

    public var promptCount: Int {
        get { userDefaults.object(forKey: Key.promptCount) as? Int ?? 0 }
        set { userDefaults.set(newValue, forKey: Key.promptCount) }
    }

}

public struct ToggleReportsManager {

    private let feature: ToggleReporting
    private var store: ToggleReportsStoring

    public init(feature: ToggleReporting, store: ToggleReportsStoring = ToggleReportsStore()) {
        self.store = store
        self.feature = feature
    }

    public mutating func recordPrompt(date: Date = Date()) {
        guard feature.isPromptLimitLogicEnabled else { return }
        if let windowStart = store.promptWindowStart, date.timeIntervalSince(windowStart) > feature.promptInterval {
            resetPromptWindow()
        } else if store.promptWindowStart == nil {
            startPromptWindow()
        }
        store.promptCount += 1

        func resetPromptWindow() {
            store.promptWindowStart = date
            store.promptCount = 0
        }

        func startPromptWindow() {
            store.promptWindowStart = date
        }
    }

    public mutating func recordDismissal(date: Date = Date()) {
        guard feature.isDismissLogicEnabled else { return }
        store.dismissedAt = date
    }

    public var shouldShowToggleReport: Bool { shouldShowToggleReport(date: Date()) }
    public func shouldShowToggleReport(date: Date = Date()) -> Bool {
        var didDismissalIntervalPass: Bool {
            guard feature.isDismissLogicEnabled else { return false }
            guard let dismissedAt = store.dismissedAt else { return true }
            let timeIntervalSinceLastDismiss = date.timeIntervalSince(dismissedAt)
            return timeIntervalSinceLastDismiss >= feature.dismissInterval
        }

        var isWithinPromptLimit: Bool {
            guard feature.isPromptLimitLogicEnabled else { return false }
            return store.promptCount < feature.maxPromptCount
        }

        return didDismissalIntervalPass && isWithinPromptLimit
    }

}
