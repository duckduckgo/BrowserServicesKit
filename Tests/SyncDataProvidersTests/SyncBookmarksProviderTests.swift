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

    var _encryptAndBase64Encode: (String) throws -> String = { value in
        if [BookmarkEntity.Constants.favoritesFolderID, BookmarkEntity.Constants.rootFolderID].contains(value) {
            return value
        }
        return "encrypted_\(value)"
    }
    var _base64DecodeAndDecrypt: (String) throws -> String = { value in
        if [BookmarkEntity.Constants.favoritesFolderID, BookmarkEntity.Constants.rootFolderID].contains(value) {
            return value
        }
        return value.dropping(prefix: "encrypted_")
    }

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
            try! context.save()
            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

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

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.rootFolder(children: ["2", "1"])]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["2", "1"])
        }
    }

    func testAppendingNewBookmarkToFolder() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3"]),
            .bookmark(id: "3")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["1", "2", "3"])
        }
    }

    func testMergingBookmarksInTheSameFolder() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
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
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["1", "2", "3"])
        }
    }

    func testAppendingNewFavorite() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2", isFavorite: true)
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3"]),
            .favoritesFolder(favorites: ["1", "2", "3"]),
            .bookmark(id: "3")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context)!

            XCTAssertEqual(favoritesFolder.favoritesArray.map(\.uuid), ["1", "2", "3"])
        }
    }

    func testMergingFavorites() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2", isFavorite: true)
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3"]),
            .favoritesFolder(favorites: ["3"]),
            .bookmark(id: "3")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context)!

            XCTAssertEqual(favoritesFolder.favoritesArray.map(\.uuid), ["1", "2", "3"])
        }
    }

    func testAppendingNewFavoriteFromSubfolder() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Folder(id: "2") {
                Bookmark(id: "3")
            }
        }

        let received: [Syncable] = [
            .favoritesFolder(favorites: ["1", "3"]),
            .folder(id: "2", children: ["3"]),
            .bookmark(id: "3")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context)!

            XCTAssertEqual(favoritesFolder.favoritesArray.map(\.uuid), ["1", "3"])
        }
    }

    func testAppendingAndReordering() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
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
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["1", "3", "2"])
        }
    }

    func testDeletingBookmarks() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["2"]),
            .bookmark(id: "1", isDeleted: true)
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["2"])
        }
    }

    func testThatDeletesForNonExistentBookmarksAreIgnored() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2"]),
            .bookmark(id: "3", isDeleted: true),
            .bookmark(id: "4", isDeleted: true),
            .bookmark(id: "5", isDeleted: true),
            .bookmark(id: "6", isDeleted: true),
            .bookmark(id: "7", isDeleted: true)
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["1", "2"])
        }
    }

    func testDeletingAndReordering() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
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
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["3", "2"])
        }
    }

    // MARK: - Deduplication

    func testThatBookmarksWithTheSameNameAndURLAreDeduplicated() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("name", id: "1", url: "url")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["2"]),
            .bookmark(id: "2", title: "name", url: "url")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["2"])
        }
    }

    func testThatBookmarksWithTheSameNameAndURLInDifferentFoldersAreDeduplicatedAndRemoteWins() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Bookmark("name", id: "10", url: "url")
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2"]),
            .folder(id: "1"),
            .folder(id: "2", children: ["3"]),
            .bookmark(id: "3", title: "name", url: "url")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            let folder1 = rootFolder.childrenArray[0]
            let folder2 = rootFolder.childrenArray[1]
            let bookmark = folder2.childrenArray[0]

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["1", "2"])
            XCTAssertTrue(folder1.childrenArray.isEmpty)
            XCTAssertEqual(folder2.childrenArray.map(\.uuid), ["3"])
            XCTAssertEqual(bookmark.uuid, "3")
            XCTAssertEqual(bookmark.title, "name")
            XCTAssertEqual(bookmark.url, "url")
        }
    }

    func testThatBookmarksWithTheSameNameAndURLAreDeduplicated2() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Folder(id: "2") {
                    Folder(id: "3") {
                        Bookmark("name", id: "4", url: "url")
                    }
                }
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .folder(id: "1", children: ["2"]),
            .folder(id: "2", children: ["3"]),
            .folder(id: "3", children: ["5"]),
            .bookmark(id: "5", title: "name", url: "url")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            let folder1 = rootFolder.childrenArray.first
            let folder2 = folder1?.childrenArray.first
            let folder3 = folder2?.childrenArray.first

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), [folder1?.uuid])
            XCTAssertEqual(folder1?.childrenArray.map(\.uuid), [folder2?.uuid])
            XCTAssertEqual(folder2?.childrenArray.map(\.uuid), [folder3?.uuid])
            XCTAssertEqual(folder3?.childrenArray.map(\.uuid), ["5"])
        }
    }

    func testThatFoldersWithTheSameNameAndParentAreDeduplicated() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Folder(id: "2") {
                    Folder("Duplicated folder", id: "3") {
                        Bookmark(id: "4")
                    }
                }
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .folder(id: "1", children: ["2"]),
            .folder(id: "2", children: ["5"]),
            .folder(id: "5", title: "Duplicated folder", children: ["6"]),
            .bookmark(id: "6")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            let folder1 = rootFolder.childrenArray.first
            let folder2 = folder1?.childrenArray.first
            let folder5 = folder2?.childrenArray.first

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), [folder1?.uuid])
            XCTAssertEqual(folder1?.childrenArray.map(\.uuid), [folder2?.uuid])
            XCTAssertEqual(folder2?.childrenArray.map(\.uuid), [folder5?.uuid])
            XCTAssertEqual(folder5?.childrenArray.map(\.uuid), ["4", "6"])
        }
    }

    func testThatFoldersWithTheSameNameAndParentAreDeduplicated2() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Folder(id: "2") {
                    Folder("Duplicated folder", id: "3") {
                        Folder(id: "4") {
                            Bookmark(id: "5")
                        }
                        Bookmark(id: "6")
                        Bookmark(id: "7")
                        Bookmark(id: "8")
                    }
                }
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .folder(id: "1", children: ["2"]),
            .folder(id: "2", children: ["9"]),
            .folder(id: "9", title: "Duplicated folder", children: ["10", "11", "12"]),
            .bookmark(id: "10"),
            .bookmark(id: "11"),
            .folder(id: "12", children: ["13"]),
            .bookmark(id: "13")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            let folder1 = rootFolder.childrenArray.first
            let folder2 = folder1?.childrenArray.first
            let folder6 = folder2?.childrenArray.first

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), [folder1?.uuid])
            XCTAssertEqual(folder1?.childrenArray.map(\.uuid), [folder2?.uuid])
            XCTAssertEqual(folder2?.childrenArray.map(\.uuid), [folder6?.uuid])
            XCTAssertEqual(folder6?.childrenArray.map(\.uuid), ["4", "6", "7", "8", "10", "11", "12"])
        }
    }

    func testThatIdenticalBookmarkTreesAreDeduplicated() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["11", "12"]),
            .folder(id: "11", title: "1"),
            .bookmark(id: "12", title: "2")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["11", "12"])
        }
    }

    func testReceivingUpdateToDeletedObject() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", isDeleted: true)
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark(id: "1", title: "test2")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        await provider.handleSyncResult(sent: sent, received: received, timestamp: "1234", crypter: crypter)

        context.performAndWait {
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            XCTAssertTrue(rootFolder.childrenArray.isEmpty)
        }
    }

    func testReceivingUpdateToDeletedObject2() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark(id: "1", title: "test2")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        context.performAndWait {
            let request = BookmarkEntity.fetchRequest()
            request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), "1")
            let bookmark = try! context.fetch(request).first!
            bookmark.markPendingDeletion()
            try! context.save()
        }

        await provider.handleSyncResult(sent: sent, received: received, timestamp: "1234", crypter: crypter)

        context.performAndWait {
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            XCTAssertTrue(rootFolder.childrenArray.isEmpty)
        }
    }

    func testThatIdenticalBookmarkTreesAreDeduplicated2() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "01") {
                Folder(id: "02") {
                    Bookmark(id: "03")
                }
                Bookmark(id: "04")
                Folder(id: "05") {
                    Bookmark(id: "06")
                    Folder(id: "07") {
                        Folder(id: "08")
                        Bookmark(id: "09")
                        Bookmark(id: "10")
                        Bookmark(id: "11")
                    }
                    Bookmark(id: "12")
                    Bookmark(id: "13")
                }
                Bookmark(id: "14")
            }
            Bookmark(id: "15")
            Folder(id: "16") {
                Folder(id: "17") {
                    Bookmark(id: "18")
                }
            }
            Bookmark(id: "19")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["101", "115", "116", "119"]),
            .folder(id: "101", title: "01", children: ["102", "104", "105", "114"]),
            .folder(id: "102", title: "02", children: ["103"]),
            .bookmark(id: "103", title: "03"),
            .bookmark(id: "104", title: "04"),
            .folder(id: "105", title: "05", children: ["106", "107", "112", "113"]),
            .bookmark(id: "106", title: "06"),
            .folder(id: "107", title: "07", children: ["108", "109", "110", "111"]),
            .folder(id: "108", title: "08"),
            .bookmark(id: "109", title: "09"),
            .bookmark(id: "110", title: "10"),
            .bookmark(id: "111", title: "11"),
            .bookmark(id: "112", title: "12"),
            .bookmark(id: "113", title: "13"),
            .bookmark(id: "114", title: "14"),
            .bookmark(id: "115", title: "15"),
            .folder(id: "116", title: "16", children: ["117"]),
            .folder(id: "117", title: "17", children: ["118"]),
            .bookmark(id: "118", title: "18"),
            .bookmark(id: "119", title: "19")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()

            provider.processReceivedBookmarks(received, in: context, using: crypter)
            try! context.save()

            let folder01 = rootFolder.childrenArray[0]
            let folder02 = folder01.childrenArray[0]
            let folder05 = folder01.childrenArray[2]
            let folder07 = folder05.childrenArray[1]
            let folder08 = folder07.childrenArray[0]
            let folder16 = rootFolder.childrenArray[2]
            let folder17 = folder16.childrenArray[0]

            XCTAssertEqual(rootFolder.childrenArray.map(\.uuid), ["101", "115", "116", "119"])
            XCTAssertEqual(folder01.childrenArray.map(\.uuid), ["102", "104", "105", "114"])
            XCTAssertEqual(folder02.childrenArray.map(\.uuid), ["103"])
            XCTAssertEqual(folder05.childrenArray.map(\.uuid), ["106", "107", "112", "113"])
            XCTAssertEqual(folder07.childrenArray.map(\.uuid), ["108", "109", "110", "111"])
            XCTAssertTrue(folder08.childrenArray.isEmpty)
            XCTAssertEqual(folder16.childrenArray.map(\.uuid), ["117"])
            XCTAssertEqual(folder17.childrenArray.map(\.uuid), ["118"])
        }
    }
}

extension SyncBookmarksProviderTests {

    func fetchAllNonRootEntities(in context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "NOT %K IN %@", #keyPath(BookmarkEntity.uuid), [BookmarkEntity.Constants.rootFolderID, BookmarkEntity.Constants.favoritesFolderID])
        request.sortDescriptors = [.init(key: #keyPath(BookmarkEntity.title), ascending: true)]
        return try! context.fetch(request)
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
            "page": ["url": url ?? title],
            "client_last_modified": "1234"
        ]
        if isDeleted {
            json["deleted"] = ""
        }
        return .init(jsonObject: json)
    }

    static func folder(id: String, title: String? = nil, children: [String] = [], lastModified: String? = nil, isDeleted: Bool = false) -> Syncable {
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
