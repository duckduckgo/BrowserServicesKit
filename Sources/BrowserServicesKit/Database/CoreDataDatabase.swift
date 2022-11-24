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

    public enum Error: Swift.Error {
        case containerLocationCouldNotBePrepared(underlyingError: Swift.Error)
    }

    private let containerLocation: URL
    private let container: NSPersistentContainer
    private var loadStoreTask: Task<NSManagedObjectContext, Swift.Error>!

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

    public init(name: String, containerLocation: URL, model: NSManagedObjectModel) {
        self.container = NSPersistentContainer(name: name, managedObjectModel: model)
        self.containerLocation = containerLocation

        let description = NSPersistentStoreDescription(url: containerLocation.appendingPathComponent("\(name).sqlite"))
        description.type = NSSQLiteStoreType

        self.container.persistentStoreDescriptions = [description]
    }

    public func loadStore() -> Task<NSManagedObjectContext, Swift.Error> {
        if let loadStoreTask = loadStoreTask {
            return loadStoreTask
        }
        self.loadStoreTask = Task.detached {
            try await Task.sleep(nanoseconds: 1000000000)
            return try await self.loadStoreAsync()
        }
        return loadStoreTask
    }

    private func loadStoreAsync() async throws -> NSManagedObjectContext {
        do {
            try FileManager.default.createDirectory(at: containerLocation, withIntermediateDirectories: true)
        } catch {
            throw Error.containerLocationCouldNotBePrepared(underlyingError: error)
        }

        return try await withCheckedThrowingContinuation { continuation in
            container.loadPersistentStores { _, error in
                if let error = error {
                    continuation.resume(with: .failure(error))
                    return
                }

                let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                context.persistentStoreCoordinator = self.container.persistentStoreCoordinator
                context.name = "Migration"
                context.perform {
                    continuation.resume(with: .success(context))
                }
            }
        }
    }

    public func makeContext(concurrencyType: NSManagedObjectContextConcurrencyType, name: String? = nil) -> MyManagedObjectContext {
        let context = MyManagedObjectContext(concurrencyType: concurrencyType, loadStoreTask: loadStoreTask)
        context.persistentStoreCoordinator = container.persistentStoreCoordinator
        context.name = name

        return context
    }

}

final public class MyManagedObjectContext: NSManagedObjectContext {
    public let loadStoreTask: Task<NSManagedObjectContext, Swift.Error>

    public override var persistentStoreCoordinator: NSPersistentStoreCoordinator? {
        get {
            let coordinator = super.persistentStoreCoordinator
            if Thread.isMainThread,
               coordinator?.persistentStores.isEmpty == true {

                let condition = RunLoop.ResumeCondition()
                Task {
                    _=await self.loadStoreTask.result
                    condition.resolve()
                }
                RunLoop.current.run(until: condition)
            }

            return coordinator
        }
        set {
            super.persistentStoreCoordinator = newValue
        }
    }

    init(concurrencyType: NSManagedObjectContextConcurrencyType, loadStoreTask: Task<NSManagedObjectContext, Swift.Error>) {
        self.loadStoreTask = loadStoreTask
        super.init(concurrencyType: concurrencyType)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, deprecated)
    public override func performAndWait(_ block: () -> Void) {
//        dispatchPrecondition(condition: .onQueue(.main))
        super.performAndWait(block)
    }


    @available(*, deprecated)
    public override func perform(_ block: @escaping () -> Void) {
        Task.detached {
            _=await self.loadStoreTask.result
            super.perform {
                block()
            }
        }
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

