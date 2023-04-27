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

            let bookmarks = fetchAllNonRootBookmarks(in: context)

            XCTAssertEqual(bookmarks.count, 3)
            XCTAssertEqual(bookmarks[0].title, "Bookmark 1")
            XCTAssertEqual(bookmarks[1].title, "Bookmark 4")
            XCTAssertEqual(bookmarks[2].title, "Bookmark 5")
            XCTAssertEqual(bookmarks[0].modifiedAt, nil)
            XCTAssertEqual(bookmarks[1].modifiedAt, nil)
            XCTAssertEqual(bookmarks[2].modifiedAt, nil)
        }
    }

}

extension SyncBookmarksProviderTests {

    func fetchAllNonRootBookmarks(in context: NSManagedObjectContext) -> [BookmarkEntity] {
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
