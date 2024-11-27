//
//  PrivacyStatsPack.swift
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

struct PrivacyStatsPack: Sendable {
    let timestamp: Date
    var trackers: [String: Int64]

    init(timestamp: Date, trackers: [String: Int64] = [:]) {
        self.timestamp = timestamp
        self.trackers = trackers
    }
}

actor CurrentPack {
    var pack: PrivacyStatsPack

    nonisolated private(set) lazy var commitChangesPublisher: AnyPublisher<PrivacyStatsPack, Never> = commitChangesSubject.eraseToAnyPublisher()
    nonisolated private let commitChangesSubject = PassthroughSubject<PrivacyStatsPack, Never>()

    private var commitTask: Task<Void, Never>?

    init(pack: PrivacyStatsPack) {
        self.pack = pack
//        pack = .init(timestamp: Date().privacyStatsPackTimestamp, trackers: [:])
    }

    func updatePack(_ pack: PrivacyStatsPack) {
        self.pack = pack
    }

    func recordBlockedTracker(_ name: String) {

        let currentTimestamp = Date().privacyStatsPackTimestamp
        if currentTimestamp != pack.timestamp {
            commitChangesSubject.send(pack)
            resetStats(andSet: currentTimestamp)
        }

        let count = pack.trackers[name] ?? 0
        pack.trackers[name] = count + 1

        commitTask?.cancel()
        commitTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)

                Logger.privacyStats.debug("Storing trackers state")
                commitChangesSubject.send(pack)
            } catch {
                // commit task got cancelled
            }
        }
    }

    private func resetStats(andSet newTimestamp: Date) {
        pack = PrivacyStatsPack(timestamp: newTimestamp, trackers: [:])
    }
}
