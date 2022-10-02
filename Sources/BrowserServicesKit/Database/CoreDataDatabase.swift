//
//  CoreDataDatabase.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import OSLog

public class CoreDataDatabase {
    
    public enum Error {
        case dbInitializationError
    }

    private let container: NSPersistentContainer
    private let storeLoadedCondition = RunLoop.ResumeCondition()
    private let log: OSLog

    public var isDatabaseFileInitialized: Bool {
        guard let containerURL = container.persistentStoreDescriptions.first?.url else { return false }

        return FileManager.default.fileExists(atPath: containerURL.path)
    }
    
    private var errorHandler: EventMapping<Error>?
    
    public var model: NSManagedObjectModel {
        return container.managedObjectModel
    }
    
    public static func loadModel(from bundle: Bundle, named name: String) -> NSManagedObjectModel? {
        guard let url = bundle.url(forResource: name, withExtension: "momd") else { return nil }
        
        return NSManagedObjectModel(contentsOf: url)
    }
    
    public init(name: String,
                url: URL,
                model: NSManagedObjectModel,
                errorHandler: EventMapping<Error>? = nil,
                log: OSLog = .disabled) {
        
        self.container = NSPersistentContainer(name: name, managedObjectModel: model)
        
        // TODO: create subdirectories if needed
        let description = NSPersistentStoreDescription(url: url.appendingPathComponent("\(name).sqlite"))
        description.type = NSSQLiteStoreType
        
        self.container.persistentStoreDescriptions = [description]
        
        self.errorHandler = errorHandler
        self.log = log
    }
    
    public func loadStore(andMigrate handler: @escaping (NSManagedObjectContext) -> Void = { _ in }) {
        
        let path = container.persistentStoreDescriptions.first?.url?.absoluteString ?? "nil"
        os_log("Loading SQL store '%s' located in %s", log: log, type: .debug, container.name, path)
        
        container.loadPersistentStores { _, error in
            if let error = error {
                self.errorHandler?.fire(.dbInitializationError, error: error)
            }
            
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = self.container.persistentStoreCoordinator
            context.name = "Migration"
            context.perform {
                handler(context)
                self.storeLoadedCondition.resolve()
            }
        }
    }
    
    public func makeContext(concurrencyType: NSManagedObjectContextConcurrencyType, name: String? = nil) -> NSManagedObjectContext {
        RunLoop.current.run(until: storeLoadedCondition)

        let context = NSManagedObjectContext(concurrencyType: concurrencyType)
        context.persistentStoreCoordinator = container.persistentStoreCoordinator
        context.name = name
        
        return context
    }
}

extension NSManagedObjectContext {
    
    public func deleteAll(entities: [NSManagedObject] = []) {
        for entity in entities {
            delete(entity)
        }
    }
    
    public func deleteAll<T: NSManagedObject>(matching request: NSFetchRequest<T>) {
            if let result = try? fetch(request) {
                deleteAll(entities: result)
            }
    }
    
    public func deleteAll(entityDescriptions: [NSEntityDescription] = []) {
        for entityDescription in entityDescriptions {
            let request = NSFetchRequest<NSManagedObject>()
            request.entity = entityDescription
            
            deleteAll(matching: request)
        }
    }
}
