//
//  HTTPSUpgradeManagedObjectModel.swift
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

import CoreData
import Persistence
extension HTTPSUpgrade {

    public static let managedObjectModel: NSManagedObjectModel = {
        // not working in `swift test`
        if let managedObjectModel = CoreDataDatabase.loadModel(from: .module, named: "HTTPSUpgrade") {
            return managedObjectModel
        }

        // create model manually
        let excludedDomainEntity = NSEntityDescription()
        excludedDomainEntity.name = NSStringFromClass(HTTPSExcludedDomain.self)
        excludedDomainEntity.managedObjectClassName = NSStringFromClass(HTTPSExcludedDomain.self)

        let excludedDomainAttribute = NSAttributeDescription()
        excludedDomainAttribute.name = #keyPath(HTTPSExcludedDomain.domain)
        excludedDomainAttribute.attributeType = .stringAttributeType

        excludedDomainEntity.properties = [excludedDomainAttribute]

        let excludedDomainIndexElementDescription = NSFetchIndexElementDescription(property: excludedDomainAttribute, collationType: NSFetchIndexElementType.binary)
        excludedDomainIndexElementDescription.isAscending = true
        let excludedDomainIndexDescription = NSFetchIndexDescription(name: "domainIndex", elements: [excludedDomainIndexElementDescription])

        excludedDomainEntity.indexes = [excludedDomainIndexDescription]

        let storedBloomFilterSpecificationEntity = NSEntityDescription()
        storedBloomFilterSpecificationEntity.name = NSStringFromClass(HTTPSStoredBloomFilterSpecification.self)
        storedBloomFilterSpecificationEntity.managedObjectClassName = NSStringFromClass(HTTPSStoredBloomFilterSpecification.self)

        let specBitCountAttribute = NSAttributeDescription()
        specBitCountAttribute.name = #keyPath(HTTPSStoredBloomFilterSpecification.bitCount)
        specBitCountAttribute.attributeType = .integer64AttributeType
        specBitCountAttribute.defaultValue = 0

        let specErrorRateAttribute = NSAttributeDescription()
        specErrorRateAttribute.name = #keyPath(HTTPSStoredBloomFilterSpecification.errorRate)
        specErrorRateAttribute.attributeType = .doubleAttributeType
        specErrorRateAttribute.defaultValue = 0

        let specSha256Attribute = NSAttributeDescription()
        specSha256Attribute.name = #keyPath(HTTPSStoredBloomFilterSpecification.sha256)
        specSha256Attribute.attributeType = .stringAttributeType

        let specTotalEntriesAttribute = NSAttributeDescription()
        specTotalEntriesAttribute.name = #keyPath(HTTPSStoredBloomFilterSpecification.totalEntries)
        specTotalEntriesAttribute.attributeType = .integer64AttributeType
        specTotalEntriesAttribute.defaultValue = 0

        storedBloomFilterSpecificationEntity.properties = [specBitCountAttribute, specErrorRateAttribute, specSha256Attribute, specTotalEntriesAttribute]

        let model = NSManagedObjectModel()
        model.entities = [excludedDomainEntity, storedBloomFilterSpecificationEntity]
        return model
    }()

}
