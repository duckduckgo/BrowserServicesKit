//
//  BookmarkEntityTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import Persistence
@testable import Bookmarks

final class BookmarkEntityTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var location: URL!

    override func setUp() {
        super.setUp()

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: className, containerLocation: location, model: model)
        bookmarksDatabase.loadStore()
    }

    override func tearDown() {
        super.tearDown()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testWhenBookmarkIsSavedThenModifiedAtIsUpdated() throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let bookmark = makeBookmark(in: context)
            XCTAssertNoThrow(try? context.save())

            let firstSaveModifiedAt = bookmark.modifiedAt
            XCTAssertNotNil(firstSaveModifiedAt)

            bookmark.url = "https://www.duck.com"

            XCTAssertNoThrow(try? context.save())

            let nextSaveModifiedAt = bookmark.modifiedAt
            XCTAssertNotNil(nextSaveModifiedAt)

            XCTAssertTrue(firstSaveModifiedAt! < nextSaveModifiedAt!)
        }
    }


    func testWhenBookmarkModificationTimestampIsUpdatedThenItIsNotOverwrittenUponSave() throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let bookmark = makeBookmark(in: context)
            XCTAssertNoThrow(try? context.save())

            let firstSaveModifiedAt = bookmark.modifiedAt
            XCTAssertNotNil(firstSaveModifiedAt)

            bookmark.modifiedAt = nil

            XCTAssertNoThrow(try? context.save())

            XCTAssertNil(bookmark.modifiedAt)
        }
    }

    func testWhenBookmarkParentChangesInTwoContextsAtTheSameTimeThenDataInconsitencyOccurs() throws {
        let c1 = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        var folder1ID: NSManagedObjectID!
        var folder2ID: NSManagedObjectID!
        var folder3ID: NSManagedObjectID!
        var bookmarkID: NSManagedObjectID!

        c1.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: c1)
            let folder1 = makeFolder(named: "Folder 1", in: c1)
            let folder2 = makeFolder(named: "Folder 2", in: c1)
            let folder3 = makeFolder(named: "Folder 3", in: c1)
            let bookmark = makeBookmark(withParent: folder1, in: c1)

            XCTAssertNoThrow(try? c1.save())
            folder1ID = folder1.objectID
            folder2ID = folder2.objectID
            folder3ID = folder3.objectID
            bookmarkID = bookmark.objectID
        }

        let c2 = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        c2.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        c1.performAndWait {
            let bookmark = c1.object(with: bookmarkID) as! BookmarkEntity
            let folder2 = c1.object(with: folder2ID) as! BookmarkEntity

            bookmark.parent = folder2
        }

        c2.performAndWait {
            let bookmark = c2.object(with: bookmarkID) as! BookmarkEntity
            let folder3 = c2.object(with: folder3ID) as! BookmarkEntity

            bookmark.parent = folder3
        }

        c1.performAndWait {
            do {
                try c1.save()
            } catch {
                XCTFail("context save failed")
            }

            let bookmark = c1.object(with: bookmarkID) as! BookmarkEntity
            let folder1 = c1.object(with: folder1ID) as! BookmarkEntity
            let folder2 = c1.object(with: folder2ID) as! BookmarkEntity
            let folder3 = c1.object(with: folder3ID) as! BookmarkEntity

            XCTAssertEqual(folder1.children?.count, 0)
            XCTAssertEqual(folder2.children?.count, 1)
            XCTAssertEqual(folder3.children?.count, 0)
            XCTAssertEqual(bookmark.parent?.title, folder2.title)
        }

        c2.performAndWait {
            do {
                try c2.save()
            } catch {
                XCTFail("context save failed")
            }


            let bookmark = c2.object(with: bookmarkID) as! BookmarkEntity
            let folder1 = c2.object(with: folder1ID) as! BookmarkEntity
            let folder2 = c2.object(with: folder2ID) as! BookmarkEntity
            let folder3 = c2.object(with: folder3ID) as! BookmarkEntity

            XCTAssertEqual(folder1.children?.count, 0)
            XCTAssertEqual(folder2.children?.count, 1)
            XCTAssertEqual(folder3.children?.count, 1)
            XCTAssertEqual(bookmark.parent?.title, folder2.title)
        }
    }

    private func makeFolder(named title: String, with parent: BookmarkEntity? = nil, in context: NSManagedObjectContext) -> BookmarkEntity {
        let parentFolder = parent ?? BookmarkUtils.fetchRootFolder(context)!
        return BookmarkEntity.makeFolder(title: title, parent: parentFolder, context: context)
    }

    private func makeBookmark(withParent parent: BookmarkEntity? = nil, in context: NSManagedObjectContext) -> BookmarkEntity {
        let parentFolder = parent ?? BookmarkUtils.fetchRootFolder(context)!
        return BookmarkEntity.makeBookmark(
            title: "Bookmark 1",
            url: "https://www.duckduckgo.com",
            parent: parentFolder,
            context: context
        )
    }
}
