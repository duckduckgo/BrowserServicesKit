//
//  BookmarkUtilsTests.swift
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
import Foundation
import Persistence
import XCTest
@testable import Bookmarks

final class BookmarkUtilsTests: XCTestCase {
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
        bookmarksDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: location, model: model)
        bookmarksDatabase.loadStore()
    }

    override func tearDown() {
        super.tearDown()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testCopyFavoritesWhenDisablingSyncInDisplayNativeMode() async throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
            Bookmark(id: "3", favoritedOn: [.mobile, .unified])
            Bookmark(id: "4", favoritedOn: [.mobile, .unified])
            Bookmark(id: "5", favoritedOn: [.desktop, .unified])
            Bookmark(id: "6", favoritedOn: [.desktop, .unified])
            Bookmark(id: "7", favoritedOn: [.desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()

            BookmarkUtils.copyFavorites(from: .mobile, to: .unified, clearingNonNativeFavoritesFolder: .desktop, in: context)

            try! context.save()

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2", favoritedOn: [.mobile, .unified])
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
                Bookmark(id: "4", favoritedOn: [.mobile, .unified])
                Bookmark(id: "5")
                Bookmark(id: "6")
                Bookmark(id: "7")
            })
        }
    }

    func testCopyFavoritesWhenDisablingSyncInDisplayAllMode() async throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
            Bookmark(id: "3", favoritedOn: [.mobile, .unified])
            Bookmark(id: "4", favoritedOn: [.mobile, .unified])
            Bookmark(id: "5", favoritedOn: [.desktop, .unified])
            Bookmark(id: "6", favoritedOn: [.desktop, .unified])
            Bookmark(id: "7", favoritedOn: [.desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()

            BookmarkUtils.copyFavorites(from: .unified, to: .mobile, clearingNonNativeFavoritesFolder: .desktop, in: context)

            try! context.save()

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2", favoritedOn: [.mobile, .unified])
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
                Bookmark(id: "4", favoritedOn: [.mobile, .unified])
                Bookmark(id: "5", favoritedOn: [.mobile, .unified])
                Bookmark(id: "6", favoritedOn: [.mobile, .unified])
                Bookmark(id: "7", favoritedOn: [.mobile, .unified])
            })
        }
    }
}
