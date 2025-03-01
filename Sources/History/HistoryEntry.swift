//
//  HistoryEntry.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

final public class HistoryEntry {

    public init(identifier: UUID,
                url: URL,
                title: String? = nil,
                failedToLoad: Bool,
                numberOfTotalVisits: Int,
                lastVisit: Date,
                visits: Set<Visit>,
                numberOfTrackersBlocked: Int,
                blockedTrackingEntities: Set<String>,
                trackersFound: Bool) {
        self.identifier = identifier
        self.url = url
        self.title = title
        self.failedToLoad = failedToLoad
        self.numberOfTotalVisits = numberOfTotalVisits
        self.lastVisit = lastVisit
        self.visits = visits
        self.numberOfTrackersBlocked = numberOfTrackersBlocked
        self.blockedTrackingEntities = blockedTrackingEntities
        self.trackersFound = trackersFound
    }

    public let identifier: UUID
    public let url: URL
    public var title: String?
    public var failedToLoad: Bool

    // MARK: - Visits

    // Kept here because of migration. Can be used as computed property once visits of HistoryEntryMO are filled with all necessary info
    // (In use for 1 month by majority of users)
    public private(set) var numberOfTotalVisits: Int
    public var lastVisit: Date

    public var visits: Set<Visit>

    func addVisit(at date: Date = Date()) -> Visit {
        let visit = Visit(date: date, historyEntry: self)
        visits.insert(visit)

        lastVisit = numberOfTotalVisits == 0 ? date : max(lastVisit, date)
        numberOfTotalVisits += 1

        return visit
    }

    // MARK: - Tracker blocking info

    public private(set) var numberOfTrackersBlocked: Int
    public private(set) var blockedTrackingEntities: Set<String>
    public var trackersFound: Bool

    public func addBlockedTracker(entityName: String) {
        numberOfTrackersBlocked += 1

        guard !entityName.trimmingWhitespace().isEmpty else {
            return
        }
        blockedTrackingEntities.insert(entityName)
    }

}

extension HistoryEntry {

    convenience init(url: URL) {
        self.init(identifier: UUID(),
                  url: url,
                  title: nil,
                  failedToLoad: false,
                  numberOfTotalVisits: 0,
                  lastVisit: Date.startOfMinuteNow,
                  visits: Set<Visit>(),
                  numberOfTrackersBlocked: 0,
                  blockedTrackingEntities: Set<String>(),
                  trackersFound: false)
    }

}

extension HistoryEntry: Hashable {

    public static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

}

extension HistoryEntry: Identifiable {}

extension HistoryEntry: NSCopying {

    public func copy(with zone: NSZone? = nil) -> Any {
        let visits = visits.compactMap { $0.copy() as? Visit }
        let entry = HistoryEntry(identifier: identifier,
                                url: url,
                                title: title,
                                failedToLoad: failedToLoad,
                                numberOfTotalVisits: numberOfTotalVisits,
                                lastVisit: lastVisit,
                                visits: Set(visits),
                                numberOfTrackersBlocked: numberOfTrackersBlocked,
                                blockedTrackingEntities: blockedTrackingEntities,
                                trackersFound: trackersFound)
        entry.visits.forEach { $0.historyEntry = entry }
        return entry
    }

}
