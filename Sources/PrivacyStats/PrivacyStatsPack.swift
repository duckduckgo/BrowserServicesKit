//
//  PrivacyStatsPack.swift
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

import Combine
import Foundation
import os.log

struct PrivacyStatsPack {
    let timestamp: Date
    var trackers: [String: Int]
}

actor CurrentPack {
    private(set) var pack: PrivacyStatsPack?
    private(set) lazy var commitChangesPublisher: AnyPublisher<PrivacyStatsPack, Never> = commitChangesSubject.eraseToAnyPublisher()

    private let commitChangesSubject = PassthroughSubject<PrivacyStatsPack, Never>()
    private var commitTask: Task<Void, Never>?

    func set(_ trackers: [String: Int], for timestamp: Date) {
        pack = .init(timestamp: timestamp, trackers: trackers)
    }

    func recordBlockedTracker(_ name: String) {

        let currentTimestamp = Date().startOfHour
        if let pack, currentTimestamp != pack.timestamp {
            commitChangesSubject.send(pack)
            resetStats(andSet: currentTimestamp)
        }

        let count = pack?.trackers[name] ?? 0
        pack?.trackers[name] = count + 1

        commitTask?.cancel()
        commitTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1000000000)

                if let pack {
                    Logger.privacyStats.debug("Storing trackers state")
                    commitChangesSubject.send(pack)
                }
            } catch {
                // commit task got cancelled
            }
        }
    }

    private func resetStats(andSet newTimestamp: Date) {
        pack = PrivacyStatsPack(timestamp: newTimestamp, trackers: [:])
    }
}
