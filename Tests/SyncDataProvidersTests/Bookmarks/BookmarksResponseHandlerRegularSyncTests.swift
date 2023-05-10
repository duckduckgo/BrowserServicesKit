//
//  BookmarksResponseHandlerRegularSyncTests.swift
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

final class BookmarksResponseHandlerRegularSyncTests: BookmarksProviderTestsBase {


    func testWhenOrphanedBookmarkIsReceivedThenItIsSaved() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.bookmark(id: "3")]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()
            let responseHandler = BookmarksResponseHandler(received: received, context: context, crypter: crypter, deduplicateEntities: false)
            responseHandler.processReceivedBookmarks()
            try! context.save()

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
                Bookmark(id: "3", isOrphaned: true)
            })
        }
    }

    func testWhenOrphanedBookmarkIsReceivedThenItIsSaved2() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Bookmark(id: "2")
                Bookmark(id: "3")
            }
        }

        let received: [Syncable] = [
            .folder(id: "1", children: ["4"]),
            .bookmark(id: "4")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = bookmarkTree.createEntities(in: context)
            try! context.save()
            let responseHandler = BookmarksResponseHandler(received: received, context: context, crypter: crypter, deduplicateEntities: false)
            responseHandler.processReceivedBookmarks()
            try! context.save()

            assertEquivalent(rootFolder, BookmarkTree {
                Folder(id: "1") {
                    Bookmark(id: "4")
                }
                Bookmark(id: "2", isOrphaned: true)
                Bookmark(id: "3", isOrphaned: true)
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "2")
                Bookmark(id: "1")
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
                Bookmark(id: "3")
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1", isOrphaned: true)
                Bookmark(id: "2", isOrphaned: true)
                Bookmark(id: "3")
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1", isFavorite: true)
                Bookmark(id: "2", isFavorite: true)
                Bookmark(id: "3", isFavorite: true)
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1", isFavorite: true, isOrphaned: true)
                Bookmark(id: "2", isFavorite: true, isOrphaned: true)
                Bookmark(id: "3", isFavorite: true)
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1", isFavorite: true)
                Folder(id: "2") {
                    Bookmark(id: "3", isFavorite: true)
                }
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1", isOrphaned: true)
                Bookmark(id: "3")
                Bookmark(id: "2")
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "2")
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "3")
                Bookmark(id: "2")
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

        await provider.handleSyncResponse(sent: sent, received: received, timestamp: "1234", crypter: crypter)

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

        await provider.handleSyncResponse(sent: sent, received: received, timestamp: "1234", crypter: crypter)

        context.performAndWait {
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            XCTAssertTrue(rootFolder.childrenArray.isEmpty)
        }
    }

    // MARK: - Responses with subtree

    func testChangesToSubtree() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3") {
                Bookmark("title", id: "4", url: "url")
            }
        }

        let received: [Syncable] = [
            .folder(id: "3", children: ["5", "4"]),
            .bookmark(id: "5", title: "title", url: "url")
        ]

        context.performAndWait {
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
                Folder(id: "3") {
                    Bookmark("title", id: "5", url: "url")
                    Bookmark("title", id: "4", url: "url")
                }
            })
        }
    }

    func testChangesToSubtree2() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3") {
                Folder(id: "4") {
                    Bookmark("title", id: "5", url: "url")
                }
                Folder(id: "6") {
                    Bookmark("title2", id: "7", url: "url2")
                }
            }
        }

        let received: [Syncable] = [
            .folder(id: "6", children: ["5"]),
            .bookmark(id: "5", title: "title", url: "url")
        ]

        context.performAndWait {
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
                Folder(id: "3") {
                    Folder(id: "4")
                    Folder(id: "6") {
                        Bookmark("title", id: "5", url: "url")
                    }
                }
                Bookmark("title2", id: "7", url: "url2", isOrphaned: true)
            })
        }
    }

    func testChangesToMultipleSubtrees() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3") {
                Folder(id: "4") {
                    Bookmark("title5", id: "5", url: "url5")
                }
                Folder(id: "6") {
                    Bookmark("title7", id: "7", url: "url7")
                }
            }
            Folder(id: "8") {
                Bookmark("title9", id: "9", url: "url9")
                Bookmark("title10", id: "10", url: "url10")
            }
            Folder(id: "11") {
                Bookmark("title12", id: "12", url: "url12")
                Bookmark("title13", id: "13", url: "url13")
            }
            Folder(id: "14") {
                Bookmark("title15", id: "15", url: "url15")
                Bookmark("title16", id: "16", url: "url16")
            }
        }

        let received: [Syncable] = [
            .folder(id: "3", children: ["6", "4"]),
            .folder(id: "8", children: ["10", "9"]),
            .folder(id: "11", children: ["12", "14", "13"]),
            .folder(id: "14", children: ["18", "15", "16"]),
            .bookmark(id: "18", title: "title16", url: "url16")
        ]

        context.performAndWait {
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: false)

            assertEquivalent(rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
                Folder(id: "3") {
                    Folder(id: "6") {
                        Bookmark("title7", id: "7", url: "url7")
                    }
                    Folder(id: "4") {
                        Bookmark("title5", id: "5", url: "url5")
                    }
                }
                Folder(id: "8") {
                    Bookmark("title10", id: "10", url: "url10")
                    Bookmark("title9", id: "9", url: "url9")
                }
                Folder(id: "11") {
                    Bookmark("title12", id: "12", url: "url12")
                    Folder(id: "14") {
                        Bookmark("title16", id: "18", url: "url16")
                        Bookmark("title15", id: "15", url: "url15")
                        Bookmark("title16", id: "16", url: "url16")
                    }
                    Bookmark("title13", id: "13", url: "url13")
                }
            })
        }
    }

    func testRootFolderAndSubtreesPresentInResponse() {

    }
}
