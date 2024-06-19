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

protocol ToggleReportsStoring {

    var dismissedAt: Date? { get set }
    var appearanceWindowStart: Date? { get set }
    var appearanceCount: Int { get set }

}

public struct ToggleReportsStore: ToggleReportsStoring {

    private enum Key {

        static let dismissedAt = "com.duckduckgo.app.toggleReports.dismissedAt"
        static let appearanceWindowStart = "com.duckduckgo.app.toggleReports.appearanceWindowStart"
        static let appearanceCount = "com.duckduckgo.app.toggleReports.appearanceCount"

    }

    private let userDefaults = UserDefaults()

    var dismissedAt: Date? {
        get { userDefaults.object(forKey: Key.dismissedAt) as? Date }
        set { userDefaults.set(newValue, forKey: Key.dismissedAt) }
    }

    var appearanceWindowStart: Date? {
        get { userDefaults.object(forKey: Key.appearanceWindowStart) as? Date }
        set { userDefaults.set(newValue, forKey: Key.appearanceWindowStart) }
    }

    var appearanceCount: Int {
        get { userDefaults.object(forKey: Key.appearanceCount) as? Int ?? 0 }
        set { userDefaults.set(newValue, forKey: Key.appearanceCount) }
    }

}

public struct ToggleReportsManager {

    private enum Constant {

        static let twoDays: TimeInterval = 48 * 60 * 60

    }

    private var store: ToggleReportsStoring

    init(store: ToggleReportsStoring = ToggleReportsStore()) {
        self.store = store
    }

    mutating func recordAppearance(date: Date = Date()) {
        if let windowStart = store.appearanceWindowStart {
            if date.timeIntervalSince(windowStart) > ToggleReportsManager.Constant.twoDays {
                store.appearanceWindowStart = date
                store.appearanceCount = 0
            }
        } else {
            store.appearanceWindowStart = date
        }
        store.appearanceCount += 1
    }

    mutating func recordDismissal(date: Date = Date()) {
        store.dismissedAt = date
    }

    var shouldShowToggleReport: Bool { shouldShowToggleReport(date: Date()) }
    func shouldShowToggleReport(date: Date = Date(),
                                minimumDismissalInterval: TimeInterval = Constant.twoDays) -> Bool {
        var didDismissalIntervalPass: Bool {
            guard let dismissedAt = store.dismissedAt else { return true }
            let timeIntervalSinceLastDismiss = date.timeIntervalSince(dismissedAt)
            return timeIntervalSinceLastDismiss >= minimumDismissalInterval
        }

        var isWithinAppearanceLimit: Bool {
            store.appearanceCount < 3
        }

        return didDismissalIntervalPass && isWithinAppearanceLimit
    }

}
