//
//  SyncBookmarksProviderTests.swift
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

import XCTest
import Bookmarks
import Common
import DDGSync
import Persistence
@testable import SyncDataProviders

struct CryptingMock: Crypting {

    var _encryptAndBase64Encode: (String) throws -> String = { $0 }
    var _base64DecodeAndDecrypt: (String) throws -> String = { $0 }

    func encryptAndBase64Encode(_ value: String) throws -> String {
        try _encryptAndBase64Encode(value)
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        try _base64DecodeAndDecrypt(value)
    }
}

final class SyncBookmarksProviderTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var bookmarksDatabaseLocation: URL!
    var metadataDatabase: CoreDataDatabase!
    var metadataDatabaseLocation: URL!
    var crypter = CryptingMock()
    var provider: SyncBookmarksProvider!

    func setUpBookmarksDatabase() {
        bookmarksDatabaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: className, containerLocation: bookmarksDatabaseLocation, model: model)
        bookmarksDatabase.loadStore()
    }

    func setUpSyncMetadataDatabase() {
        metadataDatabaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = DDGSync.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "SyncMetadata") else {
            XCTFail("Failed to load model")
            return
        }
        metadataDatabase = CoreDataDatabase(name: className, containerLocation: metadataDatabaseLocation, model: model)
        metadataDatabase.loadStore()
    }

    override func setUp() {
        super.setUp()

        setUpBookmarksDatabase()
        setUpSyncMetadataDatabase()

        provider = SyncBookmarksProvider(database: bookmarksDatabase, metadataStore: LocalSyncMetadataStore(database: metadataDatabase), reloadBookmarksAfterSync: {})
    }

    override func tearDown() {
        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: bookmarksDatabaseLocation)

        try? metadataDatabase.tearDown(deleteStores: true)
        metadataDatabase = nil
        try? FileManager.default.removeItem(at: metadataDatabaseLocation)
    }

    func testThatLastSyncTimestampIsNilByDefault() {
        XCTAssertNil(provider.lastSyncTimestamp)
    }

    func testThatLastSyncTimestampIsPersisted() {
        provider.lastSyncTimestamp = "12345"
        XCTAssertEqual(provider.lastSyncTimestamp, "12345")
    }

    func testThatSentItemsAreProperlyCleanedUp() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)

            let bookmark1 = makeBookmark(named: "Bookmark 1", in: context)
            let bookmark2 = makeBookmark(in: context)

            let folder = makeFolder(named: "Folder", in: context)
            let bookmark3 = makeBookmark(withParent: folder, in: context)

            let bookmark4 = makeBookmark(named: "Bookmark 4", in: context)
            let bookmark5 = makeBookmark(named: "Bookmark 5", in: context)

            bookmark2.markPendingDeletion()
            folder.markPendingDeletion()

            do {
                try context.save()
            } catch {
                XCTFail("Failed to save context")
            }

            let sent = [bookmark1, bookmark2, bookmark3, bookmark4, bookmark5, folder].compactMap { try? Syncable(bookmark: $0, encryptedWith: crypter) }

            provider.cleanUpSentItems(sent, in: context)

            do {
                try context.save()
            } catch {
                XCTFail("Failed to save context")
            }

            let bookmarks = fetchAllNonRootEntities(in: context)

            XCTAssertEqual(bookmarks.count, 3)

            XCTAssertEqual(bookmarks[0].title, "Bookmark 1")
            XCTAssertEqual(bookmarks[1].title, "Bookmark 4")
            XCTAssertEqual(bookmarks[2].title, "Bookmark 5")

            XCTAssertEqual(bookmarks[0].modifiedAt, nil)
            XCTAssertEqual(bookmarks[1].modifiedAt, nil)
            XCTAssertEqual(bookmarks[2].modifiedAt, nil)
        }
    }

    func testThatReceivedBookmarksAreSavedToAnEmptyDatabase() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3", "4"]),
            .bookmark(id: "1"),
            .bookmark(id: "2"),
            .bookmark(id: "3"),
            .folder(id: "4", children: ["5", "6"]),
            .bookmark(id: "5"),
            .bookmark(id: "6")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try? context.save()
            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try? context.save()

            let bookmarks = fetchAllNonRootEntities(in: context)
            let rootFolder = BookmarkUtils.fetchRootFolder(context)
            XCTAssertEqual(rootFolder?.childrenArray.map(\.uuid), ["1", "2", "3", "4"])

            XCTAssertEqual(bookmarks.count, 6)

            XCTAssertEqual(bookmarks[0].title, "1")
            XCTAssertEqual(bookmarks[1].title, "2")
            XCTAssertEqual(bookmarks[2].title, "3")
            XCTAssertEqual(bookmarks[3].title, "4")
            XCTAssertTrue(bookmarks[3].isFolder)

            XCTAssertEqual(bookmarks[4].parent?.objectID, bookmarks[3].objectID)
            XCTAssertEqual(bookmarks[5].parent?.objectID, bookmarks[3].objectID)
            XCTAssertEqual(bookmarks[4].title, "5")
            XCTAssertEqual(bookmarks[5].title, "6")
        }
    }

    func testThatBookmarksAreReorderedWithinFolder() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarksTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.rootFolder(children: ["2", "1"])]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try? context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try? context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["2", "1"])
        }
    }

    func testAppendingNewBookmarkToFolder() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarksTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3"]),
            .bookmark(id: "3")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try? context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try? context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["1", "2", "3"])
        }
    }

    func testAppendingAndReordering() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarksTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3", "2"]),
            .bookmark(id: "2"),
            .bookmark(id: "3")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try? context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try? context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["1", "3", "2"])
        }
    }

    func testDeletingAndReordering() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarksTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3", "2"]),
            .bookmark(id: "1", isDeleted: true),
            .bookmark(id: "2"),
            .bookmark(id: "3")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try? context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try? context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["3", "2"])
        }
    }
}

extension SyncBookmarksProviderTests {

    func fetchAllNonRootEntities(in context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "NOT %K IN %@", #keyPath(BookmarkEntity.uuid), [BookmarkEntity.Constants.rootFolderID, BookmarkEntity.Constants.favoritesFolderID])
        request.sortDescriptors = [.init(key: #keyPath(BookmarkEntity.title), ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    @discardableResult
    func makeFolder(named title: String, withParent parent: BookmarkEntity? = nil, in context: NSManagedObjectContext) -> BookmarkEntity {
        let parentFolder = parent ?? BookmarkUtils.fetchRootFolder(context)!
        return BookmarkEntity.makeFolder(title: title, parent: parentFolder, context: context)
    }

    @discardableResult
    func makeBookmark(named title: String = "Bookmark", withParent parent: BookmarkEntity? = nil, in context: NSManagedObjectContext) -> BookmarkEntity {
        let parentFolder = parent ?? BookmarkUtils.fetchRootFolder(context)!
        return BookmarkEntity.makeBookmark(
            title: title,
            url: "https://www.duckduckgo.com",
            parent: parentFolder,
            context: context
        )
    }
}

fileprivate extension Syncable {
    static func rootFolder(children: [String]) -> Syncable {
        .folder(id: BookmarkEntity.Constants.rootFolderID, children: children)
    }

    static func favoritesFolder(favorites: [String]) -> Syncable {
        .folder(id: BookmarkEntity.Constants.favoritesFolderID, children: favorites)
    }

    static func bookmark(id: String, title: String? = nil, url: String? = nil, lastModified: String? = nil, isDeleted: Bool = false) -> Syncable {
        var json: [String: Any] = [
            "id": id,
            "title": title ?? id,
            "page": ["url": url ?? id],
            "client_last_modified": "1234"
        ]
        if isDeleted {
            json["deleted"] = ""
        }
        return .init(jsonObject: json)
    }

    static func folder(id: String, title: String? = nil, children: [String], lastModified: String? = nil, isDeleted: Bool = false) -> Syncable {
        var json: [String: Any] = [
            "id": id,
            "title": title ?? id,
            "folder": ["children": children],
            "client_last_modified": lastModified as Any
        ]
        if isDeleted {
            json["deleted"] = ""
        }
        return .init(jsonObject: json)
    }
}
