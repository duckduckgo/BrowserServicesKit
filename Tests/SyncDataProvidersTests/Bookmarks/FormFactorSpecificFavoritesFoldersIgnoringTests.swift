//
//  FormFactorSpecificFavoritesFoldersIgnoringTests.swift
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
import BookmarksTestsUtils
import Common
import DDGSync
import Persistence
@testable import SyncDataProviders

private extension Syncable {
    static func desktopFavoritesFolder(favorites: [String]) -> Syncable {
        .folder(id: "desktop_favorites_root", children: favorites)
    }

    static func mobileFavoritesFolder(favorites: [String]) -> Syncable {
        .folder(id: "mobile_favorites_root", children: favorites)
    }
}

final class FormFactorSpecificFavoritesFoldersIgnoringTests: BookmarksProviderTestsBase {

    func testThatDesktopFavoritesFolderIsIgnored() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.desktopFavoritesFolder(favorites: ["1", "2"])]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2")
        })
    }

    func testThatMobileFavoritesFolderIsIgnored() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.mobileFavoritesFolder(favorites: ["1", "2"])]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2")
        })
    }

    func testThatDesktopFavoritesFolderDoesNotAffectReceivedFavoritesFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .favoritesFolder(favorites: ["1", "2"]),
            .desktopFavoritesFolder(favorites: ["1", "2"])
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2", isFavorite: true)
        })
    }

    func testThatMobileFavoritesFolderDoesNotAffectReceivedFavoritesFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .favoritesFolder(favorites: ["1", "2"]),
            .mobileFavoritesFolder(favorites: ["1", "2"])
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1", isFavorite: true)
            Bookmark(id: "2", isFavorite: true)
        })
    }

    // MARK: - Helpers

    func createEntitiesAndHandleSyncResponse(
        with bookmarkTree: BookmarkTree,
        sent: [Syncable] = [],
        received: [Syncable],
        clientTimestamp: Date = Date(),
        serverTimestamp: String = "1234",
        in context: NSManagedObjectContext
    ) async throws -> BookmarkEntity {

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        var rootFolder: BookmarkEntity!

        context.performAndWait {
            context.refreshAllObjects()
            rootFolder = BookmarkUtils.fetchRootFolder(context)
        }

        return rootFolder
    }
}
