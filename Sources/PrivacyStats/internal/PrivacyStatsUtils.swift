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

    static func fetchCurrentPackStats(in context: NSManagedObjectContext) -> PrivacyStatsPack {
        let timestamp = Date().startOfHour
        let request = DailyBlockedTrackersEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(DailyBlockedTrackersEntity.timestamp), timestamp as NSDate)
        request.returnsObjectsAsFaults = false

        let statsObjects = (try? context.fetch(request)) ?? []

        var pack = PrivacyStatsPack(timestamp: timestamp, trackers: [:])
        statsObjects.forEach { object in
            pack.trackers[object.companyName] = object.count
        }

        return pack
    }

    static func fetchOrInsertCurrentPacks(for companyNames: Set<String>, in context: NSManagedObjectContext) -> [DailyBlockedTrackersEntity] {
        fetchOrInsertPacks(for: Date(), companyNames: companyNames, in: context)
    }

    static func fetchOrInsertPacks(for date: Date, companyNames: Set<String>, in context: NSManagedObjectContext) -> [DailyBlockedTrackersEntity] {
        let timestamp = date.startOfHour

        let request = DailyBlockedTrackersEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K in %@",
                                        #keyPath(DailyBlockedTrackersEntity.timestamp), timestamp as NSDate,
                                        #keyPath(DailyBlockedTrackersEntity.companyName), companyNames)
        request.returnsObjectsAsFaults = false

        var statsObjects = (try? context.fetch(request)) ?? []
        let missingCompanyNames = companyNames.subtracting(statsObjects.map(\.companyName))

        for companyName in missingCompanyNames {
            statsObjects.append(DailyBlockedTrackersEntity.make(timestamp: date, companyName: companyName, context: context))
        }
        return statsObjects
    }

    static func load7DayStats(until date: Date = Date(), in context: NSManagedObjectContext) -> [String: Int64] {
        let lastTimestamp = date.startOfHour
        let firstTimestamp = lastTimestamp.daysAgo(6)

        return loadStats(since: firstTimestamp, in: context)
    }

    static func loadStats(since date: Date, in context: NSManagedObjectContext) -> [String: Int64] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "DailyBlockedTrackersEntity")

        // Predicate to filter by date range
        request.predicate = NSPredicate(format: "%K >= %@", #keyPath(DailyBlockedTrackersEntity.timestamp), date as NSDate)

        // Expression description for the sum of count
        let countExpression = NSExpression(forKeyPath: #keyPath(DailyBlockedTrackersEntity.count))
        let sumExpression = NSExpression(forFunction: "sum:", arguments: [countExpression])

        let sumExpressionDescription = NSExpressionDescription()
        sumExpressionDescription.name = "totalCount"
        sumExpressionDescription.expression = sumExpression
        sumExpressionDescription.expressionResultType = .integer64AttributeType

        // Configure the fetch request for aggregation
        request.propertiesToGroupBy = [#keyPath(DailyBlockedTrackersEntity.companyName)]
        request.propertiesToFetch = [#keyPath(DailyBlockedTrackersEntity.companyName), sumExpressionDescription]
        request.resultType = .dictionaryResultType

        let results = ((try? context.fetch(request)) as? [[String: Any]]) ?? []

        let groupedResults = results.reduce(into: [String: Int64]()) { partialResult, result in
            if let companyName = result[#keyPath(DailyBlockedTrackersEntity.companyName)] as? String,
               let totalCount = result["totalCount"] as? Int64 {
                partialResult[companyName] = totalCount
            }
        }

        return groupedResults
    }

    static func deleteOutdatedPacks(olderThan date: Date = Date(), in context: NSManagedObjectContext) {
        let thisHour = date.startOfHour
        let oldestValidTimestamp = thisHour.daysAgo(7)

        let request = DailyBlockedTrackersEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K <= %@", #keyPath(DailyBlockedTrackersEntity.timestamp), oldestValidTimestamp as NSDate)
        context.deleteAll(matching: request)
    }

    static func deleteAllStats(in context: NSManagedObjectContext) {
        context.deleteAll(matching: DailyBlockedTrackersEntity.fetchRequest())
    }
}
