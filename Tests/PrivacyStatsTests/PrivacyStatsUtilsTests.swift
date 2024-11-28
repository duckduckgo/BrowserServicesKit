//
//  PrivacyStatsUtilsTests.swift
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

import CoreData
import XCTest
@testable import PrivacyStats

final class PrivacyStatsUtilsTests: XCTestCase {

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
    // static func fetchOrInsertCurrentStats(for companyNames: Set<String>, in context: NSManagedObjectContext) -> [DailyBlockedTrackersEntity]

    /**
     * Returns a dictionary representation of blocked trackers counts grouped by company name for the current day.
     */
    // static func loadCurrentDayStats(in context: NSManagedObjectContext) -> [String: Int64]

    /**
     * Returns a dictionary representation of blocked trackers counts grouped by company name for past 7 days.
     */
    // static func load7DayStats(in context: NSManagedObjectContext) -> [String: Int64]

    /**
     * Deletes stats older than 7 days for all companies.
     */
    // static func deleteOutdatedPacks(in context: NSManagedObjectContext)

    /**
     * Deletes all stats entries in the database.
     */
    // static func deleteAllStats(in context: NSManagedObjectContext)
}
