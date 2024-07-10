//
//  TestUtils.swift
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

import Foundation
import CoreData

@objc(TestEntity)
class TestEntity: NSManagedObject {

    static let name = "TestEntity"

    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "TestEntity", in: context)!
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TestEntity> {
        return NSFetchRequest<TestEntity>(entityName: "TestEntity")
    }

    @NSManaged public var attribute: String?
    @NSManaged public var relationTo: TestEntity?
    @NSManaged public var relationFrom: TestEntity?
}

class TestModel {

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "TestEntity"
        entity.managedObjectClassName = TestEntity.name

        var properties = [NSPropertyDescription]()

        let attribute = NSAttributeDescription()
        attribute.name = "attribute"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = false
        properties.append(attribute)

        let relationTo = NSRelationshipDescription()
        let relationFrom = NSRelationshipDescription()

        relationTo.name = "relationTo"
        relationFrom.isOptional = false
        relationTo.destinationEntity = entity
        relationTo.minCount = 0
        relationTo.maxCount = 1
        relationTo.deleteRule = .nullifyDeleteRule
        relationTo.inverseRelationship = relationFrom

        relationFrom.name = "relationFrom"
        relationFrom.isOptional = false
        relationFrom.destinationEntity = entity
        relationFrom.minCount = 0
        relationFrom.maxCount = 1
        relationFrom.deleteRule = .nullifyDeleteRule
        relationFrom.inverseRelationship = relationTo

        properties.append(relationTo)
        properties.append(relationFrom)

        entity.properties = properties
        model.entities = [entity]
        return model
    }
}
