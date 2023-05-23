//
//  BookmarksProviderTests.swift
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

internal class BookmarksProviderTests: BookmarksProviderTestsBase {

    func testThatLastSyncTimestampIsNilByDefault() {
        XCTAssertNil(provider.lastSyncTimestamp)
    }

    func testThatLastSyncTimestampIsPersisted() {
        provider.lastSyncTimestamp = "12345"
        XCTAssertEqual(provider.lastSyncTimestamp, "12345")
    }

    func testThatPrepareForFirstSyncClearsLastSyncTimestampAndSetsModifiedAtForAllBookmarks() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("Bookmark 1", id: "1")
            Bookmark("Bookmark 2", id: "2")
            Folder("Folder", id: "3") {
                Bookmark("Bookmark 4", id: "4")
            }
            Bookmark("Bookmark 5", id: "5")
            Bookmark("Bookmark 6", id: "6")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        provider.lastSyncTimestamp = "12345"
        try await provider.prepareForFirstSync()
        XCTAssertNil(provider.lastSyncTimestamp)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!

            assertEquivalent(rootFolder, BookmarkTree(modifiedAtCheck: { XCTAssertNotNil($0) }) {
                Bookmark("Bookmark 1", id: "1", modifiedAtCheck: { XCTAssertNotNil($0) })
                Bookmark("Bookmark 2", id: "2", modifiedAtCheck: { XCTAssertNotNil($0) })
                Folder("Folder", id: "3", modifiedAtCheck: { XCTAssertNotNil($0) }) {
                    Bookmark("Bookmark 4", id: "4", modifiedAtCheck: { XCTAssertNotNil($0) })
                }
                Bookmark("Bookmark 5", id: "5", modifiedAtCheck: { XCTAssertNotNil($0) })
                Bookmark("Bookmark 6", id: "6", modifiedAtCheck: { XCTAssertNotNil($0) })
            })
        }
    }

    func testThatFetchChangedObjectsReturnsAllObjectsWithNonNilModifiedAt() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Folder(id: "2") {
                Bookmark(id: "3")
                Bookmark(id: "4")
                Folder(id: "5") {
                    Bookmark(id: "6")
                }
            }
            Bookmark(id: "7")
            Bookmark(id: "8")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            // clear modifiedAt for some entities
            let bookmarks = BookmarkEntity.fetchBookmarks(with: ["1", "4", "8"], in: context)
            bookmarks.forEach { $0.modifiedAt = nil }
            try! context.save()
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        XCTAssertEqual(Set(changedObjects.compactMap(\.uuid)), Set(["2", "3", "5", "6", "7"]))
    }

    func testWhenBookmarkIsSoftDeletedThenFetchChangedObjectsReturnsBookmarkAndItsParent() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Folder(id: "2") {
                Bookmark(id: "3")
                Bookmark(id: "4")
                Bookmark(id: "5")
            }
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            // clear modifiedAt for all entities
            let bookmarks = BookmarkEntity.fetchBookmarks(with: ["1", "2", "3", "4", "5"], in: context)
            bookmarks.forEach { $0.modifiedAt = nil }
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmarks(with: ["4"], in: context).first
            XCTAssertNotNil(bookmark)
            bookmark?.markPendingDeletion()
            try! context.save()
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        let changedFolder = try XCTUnwrap(changedObjects.first(where: { $0.uuid == "2"}))

        XCTAssertEqual(Set(changedObjects.compactMap(\.uuid)), Set(["2", "4"]))
        XCTAssertEqual(changedFolder.children, ["3", "5"])
    }

    func testThatSentItemsAreProperlyCleanedUp() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("Bookmark 1", id: "1")
            Bookmark("Bookmark 2", id: "2", isDeleted: true)
            Folder("Folder", id: "3", isDeleted: true) {
                Bookmark("Bookmark 4", id: "4", isDeleted: true)
            }
            Bookmark("Bookmark 5", id: "5")
            Bookmark("Bookmark 6", id: "6")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark("Bookmark 1", id: "1")
                Bookmark("Bookmark 5", id: "5")
                Bookmark("Bookmark 6", id: "6")
            })
        }
    }

    // MARK: - Initial Sync

    func testThatInitialSyncIntoEmptyDatabaseClearsModifiedAtFromAllReceivedObjects() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let received: [Syncable] = [
            .rootFolder(children: ["1", "4", "5"]),
            .folder(id: "1", children: ["2", "3"]),
            .bookmark(id: "2"),
            .bookmark(id: "3"),
            .bookmark(id: "4"),
            .bookmark(id: "5")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Folder(id: "1") {
                    Bookmark(id: "2")
                    Bookmark(id: "3")
                }
                Bookmark(id: "4")
                Bookmark(id: "5")
            })
        }
    }

    func testThatInitialSyncClearsModifiedAtFromDeduplicatedBookmark() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", url: "test")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["2"]),
            .bookmark("test", id: "2", url: "test")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark("test", id: "2", url: "test")
            })
        }
    }

    func testWhenInitialSyncAppendsBookmarksToDuplicateFolderThenFolderIsDeduplicatedAndMarkedAsModified() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder("Folder", id: "1") {
                Bookmark(id: "2")
                Bookmark(id: "3")
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["4"]),
            .folder("Folder", id: "4", children: ["5", "6"]),
            .bookmark(id: "5"),
            .bookmark(id: "6")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let clientTimestamp = Date()
        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: clientTimestamp, serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Folder("Folder", id: "4", modifiedAtCheck: { XCTAssertTrue($0! > clientTimestamp) }) {
                    Bookmark(id: "2", modifiedAtCheck: { XCTAssertNotNil($0) })
                    Bookmark(id: "3", modifiedAtCheck: { XCTAssertNotNil($0) })
                    Bookmark(id: "5", modifiedAtCheck: { XCTAssertNil($0) })
                    Bookmark(id: "6", modifiedAtCheck: { XCTAssertNil($0) })
                }
            })
        }
    }

    func testWhenThereIsMergeConflictDuringInitialSyncThenSyncResponseHandlingIsRetried() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        var willSaveCallCount = 0

        var bookmarkModificationDate: Date?
        provider.willSaveContextAfterApplyingSyncResponse = {
            willSaveCallCount += 1
            if bookmarkModificationDate != nil {
                return
            }
            context.performAndWait {
                let bookmarkTree = BookmarkTree {
                    Bookmark("test-local", id: "1")
                }
                let (rootFolder, _) = bookmarkTree.createEntities(in: context)
                // skip setting modifiedAt for rootFolder to keep unit test simpler (we don't care about checking modifiedAt for rootFolder here)
                rootFolder.shouldManageModifiedAt = false
                try! context.save()
                bookmarkModificationDate = rootFolder.childrenArray.first!.modifiedAt
            }
        }
        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        XCTAssertEqual(willSaveCallCount, 2)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark("test-local", id: "1", modifiedAt: bookmarkModificationDate)
            })
        }
    }

    // MARK: - Regular Sync

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedThenObjectIsNotDeleted() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", isDeleted: true)
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark("test2", id: "1")
            })
        }
    }

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedWithoutParentFolderThenObjectIsNotDeleted() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", isDeleted: true)
        }

        let received: [Syncable] = [
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark("test2", id: "1")
            })
        }
    }

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedThenObjectIsNotDeletedAndIsNotMovedWithinFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", isDeleted: true)
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark("test2", id: "1")
                Bookmark(id: "2")
            })
        }
    }

    func testWhenObjectWasSentAndThenDeletedLocallyAndAnUpdateIsReceivedThenTheObjectIsDeleted() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let modifiedAt = Date()
        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        context.performAndWait {
            let bookmark = BookmarkEntity.fetchBookmarks(with: ["1"], in: context).first!
            bookmark.markPendingDeletion()
            try! context.save()
        }

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.addingTimeInterval(-1), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            XCTAssertTrue(rootFolder.childrenArray.isEmpty)
        }
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteChangesAreDropped() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        var bookmarkModificationDate: Date?

        context.performAndWait {
            let bookmark = BookmarkEntity.fetchBookmarks(with: ["1"], in: context).first!
            bookmark.title = "test3"
            try! context.save()
            bookmarkModificationDate = bookmark.modifiedAt
        }

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().addingTimeInterval(-1), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark("test3", id: "1", url: "test", modifiedAt: bookmarkModificationDate)
            })
        }
    }

    func testWhenBookmarkIsMovedBetweenFoldersRemotelyAndUpdatedLocallyAfterStartingSyncThenItsModifiedAtIsNotCleared() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Bookmark("test", id: "3")
            }
            Folder(id: "2")
        }

        let received: [Syncable] = [
            .folder(id: "1", children: []),
            .folder(id: "2", children: ["3"])
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            // clear modifiedAt for all entities
            let bookmarks = BookmarkEntity.fetchBookmarks(with: ["1", "2", "3"], in: context)
            bookmarks.forEach { $0.modifiedAt = nil }
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        var bookmarkModificationDate: Date!

        context.performAndWait {
            let bookmark = BookmarkEntity.fetchBookmarks(with: ["3"], in: context).first!
            bookmark.title = "test3"
            try! context.save()
            bookmarkModificationDate = bookmark.modifiedAt
        }

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: bookmarkModificationDate.addingTimeInterval(-1), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Folder(id: "1")
                Folder(id: "2") {
                    // Bookmark retains non-nil modifiedAt, but it's newer than bookmarkModificationDate
                    // because it's updated after sync context save (bookmark object is not included in synced data
                    // but it gets updated as a side effect of sync – an update to parent).
                    Bookmark("test3", id: "3", url: "test", modifiedAtCheck: { XCTAssertTrue($0! > bookmarkModificationDate) })
                }
            })
        }
    }

    func testWhenThereIsMergeConflictDuringRegularSyncThenSyncResponseHandlingIsRetried() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        var bookmarkModificationDate: Date?
        provider.willSaveContextAfterApplyingSyncResponse = {
            if bookmarkModificationDate != nil {
                return
            }
            context.performAndWait {
                let bookmark = BookmarkEntity.fetchBookmarks(with: ["1"], in: context).first!
                bookmark.title = "test3"
                try! context.save()
                bookmarkModificationDate = bookmark.modifiedAt
            }
        }
        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark("test3", id: "1", url: "test", modifiedAt: bookmarkModificationDate)
            })
        }
    }
}
