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

public class AdClickAttributionCounter {
    
    public enum Constants {
        public static let countKey = "AdClickAttributionCounter_Count"
        public static let lastSendDateKey = "AdClickAttributionCounter_Date"
    }
    
    private let store: KeyValueStoring
    private let onSend: (_ count: Int) -> Void
    private let sendInterval: Double
    
    public init(store: KeyValueStoring,
                sendInterval: Double = 60 * 60 * 24,
                onSendRequest: @escaping (_ count: Int) -> Void) {
        self.store = store
        self.onSend = onSendRequest
        self.sendInterval = sendInterval
    }
    
    public func onAttributionActive(currentTime: Date = Date()) {
        let current = store.object(forKey: Constants.countKey) as? Int ?? 0
        store.set(current + 1, forKey: Constants.countKey)
        
        sendEventsIfNeeded(currentTime: currentTime)
    }
    
    public func sendEventsIfNeeded(currentTime: Date = Date()) {
        guard let lastSendDate = store.object(forKey: Constants.lastSendDateKey) as? Date else {
            store.set(currentTime, forKey: Constants.lastSendDateKey)
            return
        }
        
        guard abs(currentTime.timeIntervalSince(lastSendDate)) > sendInterval ,
              let current = store.object(forKey: Constants.countKey) as? Int,
              current > 0 else {
            return
        }
        
        onSend(current)
        
        store.set(0, forKey: Constants.countKey)
        store.set(currentTime, forKey: Constants.lastSendDateKey)
    }
}
