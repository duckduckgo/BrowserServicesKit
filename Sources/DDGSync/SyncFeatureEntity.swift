//
//  SyncFeatureEntity.swift
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

@objc
public class SyncFeatureEntity: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SyncFeatureEntity> {
        return NSFetchRequest<SyncFeatureEntity>(entityName: "SyncFeatureEntity")
    }

    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "SyncFeatureEntity", in: context)!
    }

    @NSManaged public var name: String
    @NSManaged public internal(set) var lastModified: String?

    public convenience init(context moc: NSManagedObjectContext) {
        self.init(entity: SyncFeatureEntity.entity(in: moc), insertInto: moc)
    }

    @discardableResult
    public static func makeFeature(with name: String, lastModified: String? = nil, in context: NSManagedObjectContext) -> SyncFeatureEntity {
        let object = SyncFeatureEntity(context: context)
        object.name = name
        object.lastModified = lastModified
        return object
    }
}
