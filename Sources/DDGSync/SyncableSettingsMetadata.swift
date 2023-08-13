//
//  SyncableSettingsMetadata.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import CoreData

@objc(SyncableSettingsMetadata)
public class SyncableSettingsMetadata: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SyncableSettingsMetadata> {
        return NSFetchRequest<SyncableSettingsMetadata>(entityName: "SyncableSettingsMetadata")
    }

    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "SyncableSettingsMetadata", in: context)!
    }

    @NSManaged public var key: String
    @NSManaged public internal(set) var lastModified: Date?

    public convenience init(context moc: NSManagedObjectContext) {
        self.init(entity: SyncableSettingsMetadata.entity(in: moc), insertInto: moc)
    }

    @discardableResult
    public static func makeSettingsMetadata(with key: String, lastModified: Date? = nil, in context: NSManagedObjectContext) -> SyncableSettingsMetadata {
        let object = SyncableSettingsMetadata(context: context)
        object.key = key
        object.lastModified = lastModified
        return object
    }
}

public enum SyncableSettingsMetadataUtils {

    public static func fetchSettingsMetadata(with key: String, in context: NSManagedObjectContext) -> SyncableSettingsMetadata? {
        let request = SyncableSettingsMetadata.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(SyncableSettingsMetadata.key), key)
        request.returnsObjectsAsFaults = true
        request.fetchLimit = 1

        return try? context.fetch(request).first
    }

    public static func fetchMetadataForSettingsPendingSync(in context: NSManagedObjectContext) throws -> [SyncableSettingsMetadata] {
        let request = SyncableSettingsMetadata.fetchRequest()
        request.predicate = NSPredicate(format: "%K != nil", #keyPath(SyncableSettingsMetadata.lastModified))

        return try context.fetch(request)
    }
}
