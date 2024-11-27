//
//  PrivacyStatsPackEntity.swift
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

@objc(PrivacyStatsPackEntity)
public class PrivacyStatsPackEntity: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PrivacyStatsPackEntity> {
        return NSFetchRequest<PrivacyStatsPackEntity>(entityName: "PrivacyStatsPackEntity")
    }

    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "PrivacyStatsPackEntity", in: context)!
    }

    @NSManaged public var blockedTrackersDictionary: [String: Int]
    @NSManaged public var timestamp: Date

    public convenience init(context moc: NSManagedObjectContext) {
        self.init(entity: PrivacyStatsPackEntity.entity(in: moc), insertInto: moc)
    }

    public static func make(timestamp: Date = Date(), context: NSManagedObjectContext) -> PrivacyStatsPackEntity {
        let object = PrivacyStatsPackEntity(context: context)
        object.blockedTrackersDictionary = [:]
        object.timestamp = timestamp.startOfHour
        return object
    }
}
