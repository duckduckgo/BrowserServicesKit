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

    func testThatSentItemsAreProperlyCleanedUp() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("Bookmark 1", id: "1", modifiedAt: Date())
            Bookmark("Bookmark 2", id: "2", modifiedAt: Date(), isDeleted: true)
            Folder("Folder", id: "3", modifiedAt: Date(), isDeleted: true) {
                Bookmark("Bookmark 4", id: "4", modifiedAt: Date(), isDeleted: true)
            }
            Bookmark("Bookmark 5", id: "5", modifiedAt: Date())
            Bookmark("Bookmark 6", id: "6", modifiedAt: Date())
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

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

        await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().addingTimeInterval(-1), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
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

        await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().addingTimeInterval(-1), serverTimestamp: "1234", crypter: crypter)

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
            .bookmark(id: "1", title: "test2")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        var bookmarkModificationDate: Date?

        context.performAndWait {
            let request = BookmarkEntity.fetchRequest()
            request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), "1")
            let bookmark = try! context.fetch(request).first!
            bookmark.title = "test3"
            try! context.save()
            bookmarkModificationDate = bookmark.modifiedAt
        }

        await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().addingTimeInterval(-1), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark("test3", id: "1", url: "test", modifiedAt: bookmarkModificationDate)
            })
        }
    }
}
