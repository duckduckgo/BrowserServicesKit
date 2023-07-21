//
//  AdClickAttributionCounter.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

/**
 Class to track and aggregate the number of page loads that have had an active exemption within a specified time period.
 */
public class AdClickAttributionCounter {
    
    public enum Constants {

        public static let pageLoadsCountKey = "AdClickAttributionCounter_Count"
        public static let lastSendAtKey = "AdClickAttributionCounter_Date"
        public static let sendInterval: Double = 60 * 60 * 24 // 24 hours

    }
    
    private let store: KeyValueStoring
    private let onSend: (_ count: Int) -> Void
    private let sendInterval: Double
    
    public init(store: KeyValueStoring = AdClickAttributionCounterStore(),
                sendInterval: Double = Constants.sendInterval,
                onSendRequest: @escaping (_ count: Int) -> Void) {
        self.store = store
        self.onSend = onSendRequest
        self.sendInterval = sendInterval
    }
    
    public func onAttributionActive(currentTime: Date = Date()) {
        store.set(pageLoadsCount + 1, forKey: Constants.pageLoadsCountKey)
        sendEventsIfNeeded(currentTime: currentTime)
    }
    
    public func sendEventsIfNeeded(currentTime: Date = Date()) {
        guard let lastSendAt else {
            store.set(currentTime, forKey: Constants.lastSendAtKey)
            return
        }
        
        guard abs(currentTime.timeIntervalSince(lastSendAt)) > sendInterval,
              pageLoadsCount > 0 else {
            return
        }
        
        onSend(pageLoadsCount)
        
        store.set(0, forKey: Constants.pageLoadsCountKey)
        store.set(currentTime, forKey: Constants.lastSendAtKey)
    }

    private var lastSendAt: Date? { store.object(forKey: Constants.lastSendAtKey) as? Date }
    private var pageLoadsCount: Int { store.object(forKey: Constants.pageLoadsCountKey) as? Int ?? 0 }

}
