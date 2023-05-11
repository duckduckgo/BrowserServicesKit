//
//  BookmarksResponseHandlerFirstSyncTests.swift
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

final class BookmarksResponseHandlerFirstSyncTests: BookmarksProviderTestsBase {

    func testThatBookmarksAreReorderedWithinFolder() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.rootFolder(children: ["2", "1"])]

        context.performAndWait {
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1", isFavorite: true)
                Bookmark(id: "2", isFavorite: true)
                Bookmark(id: "3", isFavorite: true)
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "3")
                Bookmark(id: "2")
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark("name", id: "2", url: "url")
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Folder(id: "1")
                Folder(id: "2") {
                    Bookmark("name", id: "3", url: "url")
                }
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Folder(id: "1") {
                    Folder(id: "2") {
                        Folder(id: "3") {
                            Bookmark("name", id: "5", url: "url")
                        }
                    }
                }
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Folder(id: "1") {
                    Folder(id: "2") {
                        Folder("Duplicated folder", id: "5") {
                            Bookmark(id: "4")
                            Bookmark(id: "6")
                        }
                    }
                }
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Folder(id: "1") {
                    Folder(id: "2") {
                        Folder("Duplicated folder", id: "9") {
                            Folder(id: "4") {
                                Bookmark(id: "5")
                            }
                            Bookmark(id: "6")
                            Bookmark(id: "7")
                            Bookmark(id: "8")
                            Bookmark(id: "10")
                            Bookmark(id: "11")
                            Folder(id: "12") {
                                Bookmark(id: "13")
                            }
                        }
                    }
                }
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Folder("1", id: "11")
                Bookmark("2", id: "12")
            })
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
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Folder("01", id: "101") {
                    Folder("02", id: "102") {
                        Bookmark("03", id: "103")
                    }
                    Bookmark("04", id: "104")
                    Folder("05", id: "105") {
                        Bookmark("06", id: "106")
                        Folder("07", id: "107") {
                            Folder("08", id: "108")
                            Bookmark("09", id: "109")
                            Bookmark("10", id: "110")
                            Bookmark("11", id: "111")
                        }
                        Bookmark("12", id: "112")
                        Bookmark("13", id: "113")
                    }
                    Bookmark("14", id: "114")
                }
                Bookmark("15", id: "115")
                Folder("16", id: "116") {
                    Folder("17", id: "117") {
                        Bookmark("18", id: "118")
                    }
                }
                Bookmark("19", id: "119")
            })
        }
    }

    func testAppendingBookmarksToDuplicatedFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder("Folder", id: "1") {
                Bookmark(id: "2")
                Bookmark(id: "3")
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["4"]),
            .folder(id: "4", title: "Folder", children: ["2", "3", "5", "6"]),
            .bookmark(id: "5"),
            .bookmark(id: "6")
        ]

        context.performAndWait {
            let rootFolder = createEntitiesAndProcessReceivedBookmarks(with: bookmarkTree, received: received, in: context, deduplicate: true)

            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Folder("Folder", id: "4") {
                    Bookmark(id: "2")
                    Bookmark(id: "3")
                    Bookmark(id: "5")
                    Bookmark(id: "6")
                }
            })
        }
    }

    func testRootFolderAndSubtreesPresentInResponse() {

    }
}
