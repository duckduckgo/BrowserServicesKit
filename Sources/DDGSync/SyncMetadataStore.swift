//
//  SyncMetadataStore.swift
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
import Persistence
import CoreData

public protocol SyncMetadataStore {
    func registerFeature(named name: String) throws
    func timestamp(forFeatureNamed name: String) -> String?
    func updateTimestamp(_ timestamp: String?, forFeatureNamed name: String)
}

public final class LocalSyncMetadataStore: SyncMetadataStore {

    public init(database: CoreDataDatabase) {
        self.context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
    }

    public init(context: NSManagedObjectContext) {
        self.context = context
    }

    public func registerFeature(named name: String) throws {
        var saveError: Error?

        context.performAndWait {
            if SyncFeatureUtils.fetchFeature(with: name, in: context) != nil {
                return
            }

            SyncFeatureEntity.makeFeature(with: name, in: context)
            do {
                try context.save()
            } catch {
                saveError = error
            }
        }

        if let saveError {
            throw saveError
        }
    }

    public func timestamp(forFeatureNamed name: String) -> String? {
        var lastModified: String?
        context.performAndWait {
            let feature = SyncFeatureUtils.fetchFeature(with: name, in: context)
            lastModified = feature?.lastModified
        }
        return lastModified
    }

    public func updateTimestamp(_ timestamp: String?, forFeatureNamed name: String) {
        context.performAndWait {
            SyncFeatureUtils.updateTimestamp(timestamp, forFeatureNamed: name, in: context)

            try? context.save()
        }
    }

    let context: NSManagedObjectContext
}
