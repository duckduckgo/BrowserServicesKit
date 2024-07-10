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

    func createValidEntities(in context: NSManagedObjectContext) {
        let e1 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        let e2 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        e1.attribute = "e1"
        e2.attribute = "e2"
        e1.relationTo = e2
        e2.relationTo = e1
    }

    // Tests

    func testWhenThereIsNoErrorThenDataIsSaved() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            do {
                try context.applyChangesAndSave { context in
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

            context.applyChangesAndSave { context in
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
                try context.applyChangesAndSave { context in
                    createValidEntities(in: context)

                    throw LocalError.example
                }
                XCTFail("Exception should be thrown")
            } catch {
                XCTAssertEqual(error as? LocalError, .example)
            }

            XCTAssertEqual(countEntities(in: context), 0)
        }
    }

    func testWhenThereIsExplicitErrorThenOnErrorIsCalled_Closures() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            let expectation = expectation(description: "OnError")

            context.applyChangesAndSave { context in
                self.createValidEntities(in: context)

                throw LocalError.example
            } onError: { error in
                expectation.fulfill()
                XCTAssertEqual(error as? LocalError, .example)
            } onDidSave: {
                XCTFail("Should not save")
            }

            wait(for: [expectation], timeout: 5)

            XCTAssertEqual(countEntities(in: context), 0)
        }
    }

    func testWhenThereIsSaveErrorThenOnErrorIsCalled() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            do {
                try context.applyChangesAndSave { context in
                    _ = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
                }
                XCTFail("Exception should be thrown")
            } catch {
                XCTAssertEqual(error as? LocalError, LocalError.example)
            }

            XCTAssertEqual(countEntities(in: context), 0)
        }
    }

    func testWhenThereIsSaveErrorThenOnErrorIsCalled_Closures() {
        context.performAndWait {
            XCTAssertEqual(countEntities(in: context), 0)

            let expectation = expectation(description: "OnError")

            context.applyChangesAndSave { context in
                _ = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
            } onError: { error in
                expectation.fulfill()
//                XCTAssertEqual(error as? BookmarkEntity.Error, BookmarkEntity.Error.folderHasURL)
            } onDidSave: {
                XCTFail("Should not save")
            }

            wait(for: [expectation], timeout: 5)

            XCTAssertEqual(countEntities(in: context), 0)
        }
    }

//    func testWhenThereIsMergeErrorThenSaveRetries() {
//
//        let otherContext = container.newBackgroundContext()
//
//        do {
//            try store.applyChangesAndSave { context in
//                let root = BookmarkUtils.fetchRootFolder(context)
//                _ = BookmarkEntity.makeBookmark(title: "T", url: "h", parent: root!, context: context)
//
//                otherContext.performAndWait {
//                    let root = BookmarkUtils.fetchRootFolder(otherContext)
//
//                    // Only store on first pass
//                    guard root?.childrenArray.isEmpty ?? false else { return }
//
//                    _ = BookmarkEntity.makeBookmark(title: "Inner", url: "i", parent: root!, context: otherContext)
//                    do {
//                        try otherContext.save()
//                    } catch {
//                        XCTFail("Could not save inner object")
//                    }
//                }
//            }
//        } catch {
//            XCTFail("Exception should not be thrown")
//        }
//
//        otherContext.performAndWait {
//            otherContext.reset()
//            let root = BookmarkUtils.fetchRootFolder(otherContext)
//            let children = root?.childrenArray ?? []
//
//            XCTAssertEqual(children.count, 2)
//            XCTAssertEqual(Set(children.map { $0.title }), ["T", "Inner"])
//        }
//    }
//
//    func testWhenThereIsMergeErrorThenSaveRetries_Closures() {
//
//        let otherContext = container.newBackgroundContext()
//
//        let expectation = expectation(description: "On DidSave")
//
//        store.applyChangesAndSave { context in
//            let root = BookmarkUtils.fetchRootFolder(context)
//            _ = BookmarkEntity.makeBookmark(title: "T", url: "h", parent: root!, context: context)
//
//            otherContext.performAndWait {
//                let root = BookmarkUtils.fetchRootFolder(otherContext)
//
//                // Only store on first pass
//                guard root?.childrenArray.isEmpty ?? false else { return }
//
//                _ = BookmarkEntity.makeBookmark(title: "Inner", url: "i", parent: root!, context: otherContext)
//                do {
//                    try otherContext.save()
//                } catch {
//                    XCTFail("Could not save inner object")
//                }
//            }
//        } onError: { _ in
//            XCTFail("No error expected")
//        } onDidSave: {
//            expectation.fulfill()
//        }
//
//        wait(for: [expectation], timeout: 5)
//
//        otherContext.performAndWait {
//            otherContext.reset()
//            let root = BookmarkUtils.fetchRootFolder(otherContext)
//            let children = root?.childrenArray ?? []
//
//            XCTAssertEqual(children.count, 2)
//            XCTAssertEqual(Set(children.map { $0.title }), ["T", "Inner"])
//        }
//    }
//
//    func testWhenThereIsRecurringMergeErrorThenOnErrorIsCalled() {
//        let otherContext = container.newBackgroundContext()
//
//        do {
//            try store.applyChangesAndSave { context in
//                let root = BookmarkUtils.fetchRootFolder(context)
//                _ = BookmarkEntity.makeBookmark(title: "T", url: "h", parent: root!, context: context)
//
//                otherContext.performAndWait {
//                    let root = BookmarkUtils.fetchRootFolder(otherContext)
//                    _ = BookmarkEntity.makeBookmark(title: "Inner", url: "i", parent: root!, context: otherContext)
//                    do {
//                        try otherContext.save()
//                    } catch {
//                        XCTFail("Could not save inner object")
//                    }
//                }
//            }
//            XCTFail("Should trow an error")
//        } catch {
//            if case LocalBookmarkStore.BookmarkStoreError.saveLoopError(let wrappedError) = error, let wrappedError {
//                XCTAssertEqual((wrappedError as NSError).code, NSManagedObjectMergeError)
//            } else {
//                XCTFail("Loop Error expected")
//            }
//        }
//
//        otherContext.performAndWait {
//            otherContext.reset()
//            let root = BookmarkUtils.fetchRootFolder(otherContext)
//            let children = root?.childrenArray ?? []
//
//            XCTAssertEqual(children.count, 4)
//            XCTAssertEqual(Set(children.map { $0.title }), ["Inner"])
//        }
//    }
//
//    func testWhenThereIsRecurringMergeErrorThenOnErrorIsCalled_Closures() {
//        let otherContext = container.newBackgroundContext()
//
//        let expectation = expectation(description: "OnError")
//
//        store.applyChangesAndSave { context in
//            let root = BookmarkUtils.fetchRootFolder(context)
//            _ = BookmarkEntity.makeBookmark(title: "T", url: "h", parent: root!, context: context)
//
//            otherContext.performAndWait {
//                let root = BookmarkUtils.fetchRootFolder(otherContext)
//                _ = BookmarkEntity.makeBookmark(title: "Inner", url: "i", parent: root!, context: otherContext)
//                do {
//                    try otherContext.save()
//                } catch {
//                    XCTFail("Could not save inner object")
//                }
//            }
//        } onError: { error in
//            expectation.fulfill()
//
//            if case LocalBookmarkStore.BookmarkStoreError.saveLoopError(let wrappedError) = error, let wrappedError {
//                XCTAssertEqual((wrappedError as NSError).code, NSManagedObjectMergeError)
//            } else {
//                XCTFail("Loop Error expected")
//            }
//        } onDidSave: {
//            XCTFail("Did save should not be called")
//        }
//
//        wait(for: [expectation], timeout: 5)
//
//        otherContext.performAndWait {
//            otherContext.reset()
//            let root = BookmarkUtils.fetchRootFolder(otherContext)
//            let children = root?.childrenArray ?? []
//
//            XCTAssertEqual(children.count, 4)
//            XCTAssertEqual(Set(children.map { $0.title }), ["Inner"])
//        }
//    }
//

}
