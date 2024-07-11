//
//  NSManagedObjectContextExtensionTests.swift
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

import XCTest
import CoreData
import Persistence
import Foundation

class NSManagedObjectContextExtensionTests: XCTestCase {

    enum LocalError: Error {
        case example
    }

    func tempDBDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    var db: CoreDataDatabase!
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()

        db = CoreDataDatabase(name: "Test",
                              containerLocation: tempDBDir(),
                              model: TestModel.makeModel())
        db.loadStore()
        context = db.makeContext(concurrencyType: .privateQueueConcurrencyType)
    }

    override func tearDown() async throws {

        context.reset()
        context = nil
        try db.tearDown(deleteStores: true)
        try await super.tearDown()
    }

    // Helpers

    func countEntities(in context: NSManagedObjectContext) -> Int {
        let fr = TestEntity.fetchRequest()
        return (try? context.count(for: fr)) ?? 0
    }

    @discardableResult
    func createValidEntities(in context: NSManagedObjectContext) -> (TestEntity, TestEntity) {
        let e1 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        let e2 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        e1.attribute = "e1"
        e2.attribute = "e2"
        e1.relationTo = e2
        e2.relationTo = e1

        return (e1, e2)
    }

    // Tests

    func testWhenThereIsNoErrorThenDataIsSaved() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            do {
                try context.applyChangesAndSave {
                    createValidEntities(in: context)
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(countEntities(in: context), 2)
        }
    }

    func testWhenThereIsNoErrorThenDataIsSaved_Closures() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            let expectation = expectation(description: "Did save")

            context.applyChangesAndSave {
                self.createValidEntities(in: context)
            } onError: { _ in
                XCTFail("Error not expected")
            } onDidSave: {
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5)
            XCTAssertEqual(countEntities(in: context), 2)
        }
    }

    func testWhenThereIsExplicitErrorThenOnErrorIsCalled() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            do {
                try context.applyChangesAndSave {
                    createValidEntities(in: context)

                    throw LocalError.example
                }
                XCTFail("Exception should be thrown")
            } catch {
                XCTAssertEqual(error as? LocalError, .example)
            }

            // There are still changes as save has failed
            XCTAssertEqual(countEntities(in: context), 2)
            XCTAssertEqual(context.insertedObjects.count, 2)
        }
    }

    func testWhenThereIsExplicitErrorThenOnErrorIsCalled_Closures() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            let expectation = expectation(description: "OnError")

            context.applyChangesAndSave {
                self.createValidEntities(in: context)

                throw LocalError.example
            } onError: { error in
                expectation.fulfill()
                XCTAssertEqual(error as? LocalError, .example)
            } onDidSave: {
                XCTFail("Should not save")
            }

            wait(for: [expectation], timeout: 5)

            // There are still changes as save has failed
            XCTAssertEqual(countEntities(in: context), 2)
            XCTAssertEqual(context.insertedObjects.count, 2)
        }
    }

    func testWhenThereIsSaveErrorThenOnErrorIsCalled() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            do {
                try context.applyChangesAndSave {
                    _ = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
                }
                XCTFail("Exception should be thrown")
            } catch {
                XCTAssertEqual((error as NSError).code, NSValidationMultipleErrorsError)
            }

            // There are still changes as save has failed
            XCTAssertEqual(countEntities(in: context), 1)
            XCTAssertEqual(context.insertedObjects.count, 1)
        }
    }

    func testWhenThereIsSaveErrorThenOnErrorIsCalled_Closures() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            let expectation = expectation(description: "OnError")

            context.applyChangesAndSave {
                _ = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
            } onError: { error in
                expectation.fulfill()
                XCTAssertEqual((error as NSError).code, NSValidationMultipleErrorsError)
            } onDidSave: {
                XCTFail("Should not save")
            }

            wait(for: [expectation], timeout: 5)

            // There are still changes as save has failed
            XCTAssertEqual(countEntities(in: context), 1)
            XCTAssertEqual(context.insertedObjects.count, 1)
        }
    }

    func testWhenThereIsMergeErrorThenSaveRetries() {

        let otherContext = db.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            let (e1, _) = createValidEntities(in: context)
            try! context.save()

            let e1ObjectID = e1.objectID

            do {
                try context.applyChangesAndSave {

                    // Try to modify e1
                    let localE1 = try! context.existingObject(with: e1ObjectID) as! TestEntity
                    localE1.attribute = "Local name"

                    // Trigger merge error by making changes in other context to the same entity
                    otherContext.performAndWait {
                        let innerE1 = try! otherContext.existingObject(with: e1ObjectID) as! TestEntity

                        // Trigger the error only once
                        guard innerE1.attribute != "Inner name" else { return }

                        innerE1.attribute = "Inner name"

                        do {
                            try otherContext.save()
                        } catch {
                            XCTFail("Could not save inner object: \(error)")
                        }
                    }
                }
            } catch {
                XCTFail("Exception should not be thrown")
            }

            context.reset()
            let storedE1 = try! context.existingObject(with: e1ObjectID) as! TestEntity
            XCTAssertEqual(storedE1.attribute, "Local name")
        }
    }

    func testWhenThereIsMergeErrorThenSaveRetries_Closures() {

        let otherContext = db.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let expectation = expectation(description: "On DidSave")

        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            let (e1, _) = createValidEntities(in: context)
            try! context.save()

            let e1ObjectID = e1.objectID

            context.applyChangesAndSave {

                // Try to modify e1
                let localE1 = try! context.existingObject(with: e1ObjectID) as! TestEntity
                localE1.attribute = "Local name"

                // Trigger merge error by making changes in other context to the same entity
                otherContext.performAndWait {
                    let innerE1 = try! otherContext.existingObject(with: e1ObjectID) as! TestEntity

                    // Trigger the error only once
                    guard innerE1.attribute != "Inner name" else { return }

                    innerE1.attribute = "Inner name"

                    do {
                        try otherContext.save()
                    } catch {
                        XCTFail("Could not save inner object: \(error)")
                    }
                }

            } onError: { _ in
                XCTFail("No error expected")
            } onDidSave: {
                expectation.fulfill()
            }

            context.reset()
            let storedE1 = try! context.existingObject(with: e1ObjectID) as! TestEntity
            XCTAssertEqual(storedE1.attribute, "Local name")
        }

        wait(for: [expectation], timeout: 5)
    }

    func testWhenThereIsRecurringMergeErrorThenOnErrorIsCalled() {

        let otherContext = db.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            let (e1, _) = createValidEntities(in: context)
            try! context.save()

            let e1ObjectID = e1.objectID

            do {
                try context.applyChangesAndSave {

                    // Try to modify e1
                    let localE1 = try! context.existingObject(with: e1ObjectID) as! TestEntity
                    localE1.attribute = "Local name"

                    // Trigger merge error by making changes in other context to the same entity
                    otherContext.performAndWait {
                        let innerE1 = try! otherContext.existingObject(with: e1ObjectID) as! TestEntity
                        innerE1.attribute = "Inner name"

                        do {
                            try otherContext.save()
                        } catch {
                            XCTFail("Could not save inner object: \(error)")
                        }
                    }
                }
                XCTFail("Should trow an error")
            } catch {
                if case NSManagedObjectContext.PersistenceError.saveLoopError(let wrappedError) = error, let wrappedError {
                    XCTAssertEqual((wrappedError as NSError).code, NSManagedObjectMergeError)
                } else {
                    XCTFail("Loop Error expected")
                }
            }

            context.reset()
            let storedE1 = try! context.existingObject(with: e1ObjectID) as! TestEntity
            XCTAssertEqual(storedE1.attribute, "Inner name")
        }
    }

    func testWhenThereIsRecurringMergeErrorThenOnErrorIsCalled_Closures() {
        let otherContext = db.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let expectation = expectation(description: "On Error")

        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            let (e1, _) = createValidEntities(in: context)
            try! context.save()

            let e1ObjectID = e1.objectID

            context.applyChangesAndSave {

                // Try to modify e1
                let localE1 = try! context.existingObject(with: e1ObjectID) as! TestEntity
                localE1.attribute = "Local name"

                // Trigger merge error by making changes in other context to the same entity
                otherContext.performAndWait {
                    let innerE1 = try! otherContext.existingObject(with: e1ObjectID) as! TestEntity
                    innerE1.attribute = "Inner name"

                    do {
                        try otherContext.save()
                    } catch {
                        XCTFail("Could not save inner object: \(error)")
                    }
                }

            } onError: { error in
                if case NSManagedObjectContext.PersistenceError.saveLoopError(let wrappedError) = error, let wrappedError {
                    XCTAssertEqual((wrappedError as NSError).code, NSManagedObjectMergeError)
                } else {
                    XCTFail("Loop Error expected")
                }
                expectation.fulfill()
            } onDidSave: {
                XCTFail("Save not expected")
            }

            context.reset()
            let storedE1 = try! context.existingObject(with: e1ObjectID) as! TestEntity
            XCTAssertEqual(storedE1.attribute, "Inner name")
        }

        wait(for: [expectation], timeout: 5)
    }


}
