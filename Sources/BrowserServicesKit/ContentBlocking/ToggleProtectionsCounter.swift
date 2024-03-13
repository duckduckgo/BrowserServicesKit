//
//  ToggleProtectionsCounter.swift
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
import Persistence
import Common

public enum ToggleProtectionsCounterEvent {

    enum Parameter {

        static let onCountKey = "onCount"
        static let offCountKey = "offCount"

    }

    case toggleProtectionsCounterDaily

}

/// This class aggregates protection toggles and stores that count over 24 hours.
public class ToggleProtectionsCounter {

    public enum Constant {

        public static let onCountKey = "ToggleProtectionsCounter_On_Count"
        public static let offCountKey = "ToggleProtectionsCounter_Off_Count"
        public static let lastSendAtKey = "ToggleProtectionsCounter_Date"
        public static let sendInterval: Double = 60 * 60 * 24 // 24 hours

    }

    private let store: KeyValueStoring
    private let sendInterval: TimeInterval
    private let eventReporting: EventMapping<ToggleProtectionsCounterEvent>?

    public init(store: KeyValueStoring = ToggleProtectionsCounterStore(),
                sendInterval: TimeInterval = Constant.sendInterval,
                eventReporting: EventMapping<ToggleProtectionsCounterEvent>?) {
        self.store = store
        self.sendInterval = sendInterval
        self.eventReporting = eventReporting
    }

    public func onToggleOn(currentTime: Date = Date()) {
        save(toggleOnCount: toggleOnCount + 1)
        sendEventsIfNeeded(currentTime: currentTime)
    }

    public func onToggleOff(currentTime: Date = Date()) {
        save(toggleOffCount: toggleOffCount + 1)
        sendEventsIfNeeded(currentTime: currentTime)
    }

    public func sendEventsIfNeeded(currentTime: Date = Date()) {
        guard let lastSendAt else {
            save(lastSendAt: currentTime)
            return
        }

        if currentTime.timeIntervalSince(lastSendAt) > sendInterval {
            eventReporting?.fire(.toggleProtectionsCounterDaily, parameters: [
                ToggleProtectionsCounterEvent.Parameter.onCountKey: String(toggleOnCount),
                ToggleProtectionsCounterEvent.Parameter.offCountKey: String(toggleOffCount)
            ])
            resetStats(currentTime: currentTime)
        }
    }

    private func resetStats(currentTime: Date = Date()) {
        save(toggleOnCount: 0)
        save(toggleOffCount: 0)
        save(lastSendAt: currentTime)
    }

    // MARK: - Store

    private var lastSendAt: Date? { store.object(forKey: Constant.lastSendAtKey) as? Date }
    private var toggleOnCount: Int { store.object(forKey: Constant.onCountKey) as? Int ?? 0 }
    private var toggleOffCount: Int { store.object(forKey: Constant.offCountKey) as? Int ?? 0 }

    private func save(lastSendAt: Date) {
        store.set(lastSendAt, forKey: Constant.lastSendAtKey)
    }

    private func save(toggleOnCount: Int) {
        store.set(toggleOnCount, forKey: Constant.onCountKey)
    }

    private func save(toggleOffCount: Int) {
        store.set(toggleOffCount, forKey: Constant.offCountKey)
    }

}
