//
//  PrivacyStatsUtils.swift
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

import Common
import CoreData
import Foundation

final class PrivacyStatsUtils {

    static func loadStats(for date: Date = Date(), in context: NSManagedObjectContext) -> PrivacyStatsEntity {
        let timestamp = date.startOfHour

        let request = PrivacyStatsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(PrivacyStatsEntity.timestamp), timestamp as NSDate)
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false

        var statsObject = ((try? context.fetch(request)) ?? []).first
        if statsObject == nil {
            statsObject = PrivacyStatsEntity.make(timestamp: date, context: context)
        }
        return statsObject!
    }

    static func load7DayStats(until date: Date = Date(), in context: NSManagedObjectContext) -> [String: Int] {
        let lastTimestamp = date.startOfHour
        let firstTimestamp = lastTimestamp.daysAgo(7)

        return loadStats(from: firstTimestamp, to: lastTimestamp, in: context)
    }

    static func loadStats(from startDate: Date, to endDate: Date, in context: NSManagedObjectContext) -> [String: Int] {
        let request = PrivacyStatsEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K >= %@ AND %K < %@",
            #keyPath(PrivacyStatsEntity.timestamp),
            startDate as NSDate,
            #keyPath(PrivacyStatsEntity.timestamp),
            endDate as NSDate
        )
        request.returnsObjectsAsFaults = false

        let statsObjects = (try? context.fetch(request)) ?? []
        return statsObjects.reduce(into: [String: Int]()) { partialResult, stats in
            partialResult.merge(stats.blockedTrackersDictionary, uniquingKeysWith: +)
        }
    }
}
