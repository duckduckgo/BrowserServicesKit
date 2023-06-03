//
//  BookmarkListViewModelTests.swift
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

import BookmarksTestsUtils
import Common
import Persistence
import XCTest
@testable import Bookmarks

class MockBookmarksModelErrorEventMapping: EventMapping<BookmarksModelError> {
//    var events: [BookmarksModelError] = []

    // swiftlint:disable:next cyclomatic_complexity
    init() {
        super.init { event, error, _, _ in
//            self?.events.append(event)
        }
    }

    override init(mapping: @escaping EventMapping<BookmarksModelError>.Mapping) {
        fatalError("Use init()")
    }
}

final class BookmarkListViewModelTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var bookmarkListViewModel: BookmarkListViewModel!
    var eventMapping: MockBookmarksModelErrorEventMapping!
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
        bookmarkListViewModel = BookmarkListViewModel(bookmarksDatabase: bookmarksDatabase, parentID: nil, errorEvents: eventMapping)

        eventMapping = MockBookmarksModelErrorEventMapping()
    }

    override func tearDown() {
        super.tearDown()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testWhenOrphanedBookmarkIsMovedThenItIsAttachedToRootFolder() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", isOrphaned: true)
        }

        BookmarkUtils.prepareFoldersStructure(in: context)
        bookmarkTree.createEntities(in: context)
        try! context.save()

        let bookmark = BookmarkEntity.fetchBookmark(withUUID: "2", context: context)!

        bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 1, toIndex: 0)

        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "2")
            Bookmark(id: "1")
        })
    }

    func testWhenOrphanedBookmarkIsMovedUpThenAllOrphanedBookmarksBeforeItAreAttachedToRootFolder() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", isOrphaned: true)
            Bookmark(id: "3", isOrphaned: true)
            Bookmark(id: "4", isOrphaned: true)
            Bookmark(id: "5", isOrphaned: true)
            Bookmark(id: "6", isOrphaned: true)
        }

        BookmarkUtils.prepareFoldersStructure(in: context)
        bookmarkTree.createEntities(in: context)
        try! context.save()

        let bookmark = BookmarkEntity.fetchBookmark(withUUID: "5", context: context)!

        bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 4, toIndex: 2)

        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "5")
            Bookmark(id: "3")
            Bookmark(id: "4")
            Bookmark(id: "6", isOrphaned: true)
        })
    }

    func testWhenOrphanedBookmarkIsMovedDownThenAllOrphanedBookmarksBeforeToIndexAreAttachedToRootFolder() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", isOrphaned: true)
            Bookmark(id: "3", isOrphaned: true)
            Bookmark(id: "4", isOrphaned: true)
            Bookmark(id: "5", isOrphaned: true)
            Bookmark(id: "6", isOrphaned: true)
        }

        BookmarkUtils.prepareFoldersStructure(in: context)
        bookmarkTree.createEntities(in: context)
        try! context.save()

        let bookmark = BookmarkEntity.fetchBookmark(withUUID: "3", context: context)!

        bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 2, toIndex: 4)

        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "4")
            Bookmark(id: "5")
            Bookmark(id: "3")
            Bookmark(id: "6", isOrphaned: true)
        })
    }

    func testWhenBookmarkIsMovedBelowOrphanedBookmarkThenAllOrphanedBookmarksBeforeToIndexAreAttachedToRootFolder() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", isOrphaned: true)
            Bookmark(id: "3", isOrphaned: true)
            Bookmark(id: "4", isOrphaned: true)
            Bookmark(id: "5", isOrphaned: true)
            Bookmark(id: "6", isOrphaned: true)
        }

        BookmarkUtils.prepareFoldersStructure(in: context)
        bookmarkTree.createEntities(in: context)
        try! context.save()

        let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

        bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 0, toIndex: 3)

        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "2")
            Bookmark(id: "3")
            Bookmark(id: "4")
            Bookmark(id: "1")
            Bookmark(id: "5", isOrphaned: true)
            Bookmark(id: "6", isOrphaned: true)
        })
    }
}

private extension BookmarkEntity {
    static func fetchBookmark(withUUID uuid: String, context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), uuid)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
