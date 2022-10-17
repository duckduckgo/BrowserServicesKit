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
import Common
import OSLog

public protocol ManagedObjectContextFactory {
    
    func makeContext(concurrencyType: NSManagedObjectContextConcurrencyType, name: String?) -> NSManagedObjectContext
}

public class CoreDataDatabase: ManagedObjectContextFactory {
    
    public enum Error: Swift.Error {
        case containerLocationCouldNotBePrepared(underlyingError: Swift.Error)
    }

    private let containerLocation: URL
    private let container: NSPersistentContainer
    private let storeLoadedCondition = RunLoop.ResumeCondition()

    public var isDatabaseFileInitialized: Bool {
        guard let containerURL = container.persistentStoreDescriptions.first?.url else { return false }

        return FileManager.default.fileExists(atPath: containerURL.path)
    }
    
    public var model: NSManagedObjectModel {
        return container.managedObjectModel
    }
    
    public static func loadModel(from bundle: Bundle, named name: String) -> NSManagedObjectModel? {
        guard let url = bundle.url(forResource: name, withExtension: "momd") else { return nil }
        
        return NSManagedObjectModel(contentsOf: url)
    }
    
    public init(name: String,
                containerLocation: URL,
                model: NSManagedObjectModel) {
        
        self.container = NSPersistentContainer(name: name, managedObjectModel: model)
        self.containerLocation = containerLocation
        
        let description = NSPersistentStoreDescription(url: containerLocation.appendingPathComponent("\(name).sqlite"))
        description.type = NSSQLiteStoreType
        
        self.container.persistentStoreDescriptions = [description]
    }
    
    public func loadStore(completion: @escaping (NSManagedObjectContext?, Swift.Error?) -> Void = { _, _ in }) {
        
        do {
            try FileManager.default.createDirectory(at: containerLocation, withIntermediateDirectories: true)
        } catch {
            completion(nil, Error.containerLocationCouldNotBePrepared(underlyingError: error))
            return
        }
            
        container.loadPersistentStores { _, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = self.container.persistentStoreCoordinator
            context.name = "Migration"
            context.perform {
                completion(context, nil)
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
