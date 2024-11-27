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
import Persistence

final class PrivacyStatsUtils {

    static func loadCurrentPack(in context: NSManagedObjectContext) -> PrivacyStatsPackEntity {
        loadPack(for: Date(), in: context)
    }

    static func loadPack(for date: Date, in context: NSManagedObjectContext) -> PrivacyStatsPackEntity {
        let timestamp = date.startOfHour

        let request = PrivacyStatsPackEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(PrivacyStatsPackEntity.timestamp), timestamp as NSDate)
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false

        var statsObject = ((try? context.fetch(request)) ?? []).first
        if statsObject == nil {
            statsObject = PrivacyStatsPackEntity.make(timestamp: date, context: context)
        }
        return statsObject!
    }

    static func load7DayStats(until date: Date = Date(), in context: NSManagedObjectContext) -> [String: Int] {
        let lastTimestamp = date.startOfHour
        let firstTimestamp = lastTimestamp.daysAgo(7)

        return loadStats(from: firstTimestamp, to: lastTimestamp, in: context)
    }

    static func loadStats(from startDate: Date, to endDate: Date, in context: NSManagedObjectContext) -> [String: Int] {
        let request = PrivacyStatsPackEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K > %@ AND %K < %@",
            #keyPath(PrivacyStatsPackEntity.timestamp),
            startDate as NSDate,
            #keyPath(PrivacyStatsPackEntity.timestamp),
            endDate as NSDate
        )
        request.returnsObjectsAsFaults = false

        let statsObjects = (try? context.fetch(request)) ?? []
        return statsObjects.reduce(into: [String: Int]()) { partialResult, stats in
            partialResult.merge(stats.blockedTrackersDictionary, uniquingKeysWith: +)
        }
    }

    static func deleteOutdatedPacks(olderThan date: Date = Date(), in context: NSManagedObjectContext) {
        let thisHour = date.startOfHour
        let oldestValidTimestamp = thisHour.daysAgo(7)

        let request = PrivacyStatsPackEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K <= %@", #keyPath(PrivacyStatsPackEntity.timestamp), oldestValidTimestamp as NSDate)
        context.deleteAll(matching: request)
    }

    static func deleteAllStats(in context: NSManagedObjectContext) {
        context.deleteAll(matching: PrivacyStatsPackEntity.fetchRequest())
    }
}
