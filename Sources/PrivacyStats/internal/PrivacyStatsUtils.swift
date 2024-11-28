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

    /**
     * Returns objects corresponding to current stats for companies specified by `companyNames`.
     *
     * If an object doesn't exist (no trackers for a given company were reported on a given day)
     * then a new object for that company is inserted into the context and returned.
     * If a user opens the app for the first time on a given day, the database will not contain
     * any records for that day and this function will only insert new objects.
     *
     * > Note: `current stats` refer to stats objects that are active on a given day, i.e. their
     *   timestamp's day matches current day.
     */
    static func fetchOrInsertCurrentStats(for companyNames: Set<String>, in context: NSManagedObjectContext) -> [DailyBlockedTrackersEntity] {
        let timestamp = Date().privacyStatsPackTimestamp

        let request = DailyBlockedTrackersEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K in %@",
                                        #keyPath(DailyBlockedTrackersEntity.timestamp), timestamp as NSDate,
                                        #keyPath(DailyBlockedTrackersEntity.companyName), companyNames)
        request.returnsObjectsAsFaults = false

        var statsObjects = (try? context.fetch(request)) ?? []
        let missingCompanyNames = companyNames.subtracting(statsObjects.map(\.companyName))

        for companyName in missingCompanyNames {
            statsObjects.append(DailyBlockedTrackersEntity.make(timestamp: timestamp, companyName: companyName, context: context))
        }
        return statsObjects
    }

    /**
     * Returns a dictionary representation of blocked trackers counts grouped by company name for the current day.
     */
    static func loadCurrentDayStats(in context: NSManagedObjectContext) -> [String: Int64] {
        let startDate = Date().privacyStatsPackTimestamp
        return loadBlockedTrackerStats(since: startDate, in: context)
    }

    /**
     * Returns a dictionary representation of blocked trackers counts grouped by company name for past 7 days.
     */
    static func load7DayStats(in context: NSManagedObjectContext) -> [String: Int64] {
        let startDate = Date().privacyStatsOldestPackTimestamp
        return loadBlockedTrackerStats(since: startDate, in: context)
    }

    private static func loadBlockedTrackerStats(since startDate: Date, in context: NSManagedObjectContext) -> [String: Int64] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "DailyBlockedTrackersEntity")
        request.predicate = NSPredicate(format: "%K >= %@", #keyPath(DailyBlockedTrackersEntity.timestamp), startDate as NSDate)

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

    /**
     * Deletes stats older than 7 days for all companies.
     */
    static func deleteOutdatedPacks(in context: NSManagedObjectContext) {
        let oldestValidTimestamp = Date().privacyStatsOldestPackTimestamp

        let request = DailyBlockedTrackersEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K < %@", #keyPath(DailyBlockedTrackersEntity.timestamp), oldestValidTimestamp as NSDate)
        context.deleteAll(matching: request)
    }

    /**
     * Deletes all stats entries in the database.
     */
    static func deleteAllStats(in context: NSManagedObjectContext) {
        context.deleteAll(matching: DailyBlockedTrackersEntity.fetchRequest())
    }
}
