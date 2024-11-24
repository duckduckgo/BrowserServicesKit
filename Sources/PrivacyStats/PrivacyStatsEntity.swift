//
//  PrivacyStatsEntity.swift
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

@objc(PrivacyStatsEntity)
public class PrivacyStatsEntity: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PrivacyStatsEntity> {
        return NSFetchRequest<PrivacyStatsEntity>(entityName: "PrivacyStatsEntity")
    }

    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "PrivacyStatsEntity", in: context)!
    }

    @NSManaged public var blockedTrackersDictionary: [String: Int]
    @NSManaged public var timestamp: Date

    public convenience init(context moc: NSManagedObjectContext) {
        self.init(entity: PrivacyStatsEntity.entity(in: moc), insertInto: moc)
    }

    public static func make(name: String, timestamp: Date = Date(), context: NSManagedObjectContext) -> PrivacyStatsEntity {
        let object = PrivacyStatsEntity(context: context)
        object.blockedTrackersDictionary = [:]
        object.timestamp = timestamp.startOfHour
        return object
    }

    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validate()
    }

    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        try validate()
    }
}

// MARK: Validation
extension PrivacyStatsEntity {

    func validate() throws {
        try validateFavoritesFolder()
    }

    func validateFavoritesFolder() throws {
        let uuids = Set(favoriteFoldersSet.compactMap(\.uuid))
        guard uuids.isSubset(of: Constants.favoriteFoldersIDs) else {
            throw Error.invalidFavoritesFolder
        }
    }
}
