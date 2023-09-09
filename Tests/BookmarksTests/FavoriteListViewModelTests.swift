//
//  FavoriteListViewModelTests.swift
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

final class FavoriteListViewModelTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var favoriteListViewModel: FavoritesListViewModel!
    var eventMapping: MockBookmarksModelErrorEventMapping!
    var firedEvents: [BookmarksModelError] = []
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
        eventMapping = MockBookmarksModelErrorEventMapping { [weak self] event in
            self?.firedEvents.append(event)
        }

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        favoriteListViewModel = FavoritesListViewModel(bookmarksDatabase: bookmarksDatabase,
                                                       favoritesDisplayMode: .displayNative(.mobile),
                                                       errorEvents: eventMapping)
    }

    override func tearDown() {
        super.tearDown()
        firedEvents.removeAll()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testWhenBookmarkIsDeletedAndAnotherIsMovedThenNoErrorIsFired() {

        let context = favoriteListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .all], isDeleted: true)
            Bookmark(id: "2", favoritedOn: [.mobile, .all])
            Bookmark(id: "3", favoritedOn: [.mobile, .all], isDeleted: true)
            Bookmark(id: "4", favoritedOn: [.mobile, .all])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()

            let favoriteFolderUUID = favoriteListViewModel.favoritesDisplayMode.displayedPlatform.rawValue
            let rootFavoriteFolder = BookmarkUtils.fetchFavoritesFolder(withUUID: favoriteFolderUUID, in: context)!
            XCTAssertEqual(rootFavoriteFolder.favoritesArray.map(\.title), ["2", "4"])

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "2", context: context)!
            favoriteListViewModel.reloadData()
            favoriteListViewModel.moveFavorite(bookmark, fromIndex: 0, toIndex: 1)
            context.refreshAllObjects()

            XCTAssertEqual(rootFavoriteFolder.favoritesArray.map(\.title), ["4", "2"])
            XCTAssertEqual(firedEvents, [])
        }
    }

}
