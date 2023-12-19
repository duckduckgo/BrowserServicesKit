//
//  SyncDailyStatus.swift
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

public class SyncDailyStatus {

    public enum Constants {
        public static let dailyStatusDictKey = "dailyStatusDictKey"
        public static let syncCountParam = "sync_count"
        public static let lastSentDate = "dailyStatus_last_sent_date"
    }

    private let store: KeyValueStoring
    private let lock = NSLock()

    init(store: KeyValueStoring = UserDefaults()) {
        self.store = store
    }

    func onSyncFinished(with error: SyncOperationError?) {

        var updatedKeys = [Constants.syncCountParam]

        if let perFeatureErrors = error?.perFeatureErrors {
            for (feature, error) in perFeatureErrors {
                if let featureError = error as? SyncError,
                   let knownError = ErrorType(syncError: featureError) {
                    updatedKeys.append(knownError.key(for: feature))
                }
            }
        }

        lock.lock()

        var storeValues: [String: Int] = (store.object(forKey: Constants.dailyStatusDictKey) as? [String: Int]) ?? [:]

        for updatedKey in updatedKeys {
            storeValues[updatedKey] = (storeValues[updatedKey] ?? 0) + 1
        }

        store.set(storeValues, forKey: Constants.dailyStatusDictKey)

        lock.unlock()
    }

    public func sendStatusIfNeeded(currentDate: Date = Date(),
                                   handler: ([String: String]) -> Void) {
        guard let lastDate = store.object(forKey: Constants.lastSentDate) as? Date else {
            store.set(currentDate, forKey: Constants.lastSentDate)
            return
        }

        guard !Calendar.current.isDateInToday(lastDate) else { return }

        lock.lock()
        if let currentStatusData = (store.object(forKey: Constants.dailyStatusDictKey) as? [String: Int]) {
            handler(currentStatusData.mapValues({ "\($0)" }))
        }

        store.removeObject(forKey: Constants.dailyStatusDictKey)
        store.set(currentDate, forKey: Constants.lastSentDate)
        lock.unlock()
    }

    enum ErrorType {
        case objectLimitExceeded
        case requestSizeLimitExceeded
        case validation
        case requestLimitExceeded

        init?(syncError: SyncError) {
            guard case .unexpectedStatusCode(let code) = syncError else { return nil }

            switch code {
            case 409:
                self = .objectLimitExceeded
            case 413:
                self = .requestSizeLimitExceeded
            case 400:
                self = .validation
            case 418, 429:
                self = .requestLimitExceeded
            default:
                return nil
            }
        }

        var asString: String {
            switch self {
            case .objectLimitExceeded:
                return "object_limit_exceeded"
            case .requestSizeLimitExceeded:
                return "request_size_limit_exceeded"
            case .validation:
                return "validation_error"
            case .requestLimitExceeded:
                return "too_many_requests"
            }
        }

        func key(for feature: Feature) -> String {
            "\(feature.name)_\(asString)_count"
        }
    }
}
