//
//  BookmarksModel.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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


import CoreData
import Combine

public protocol BookmarkStoring {

    var updates: AnyPublisher<Void, Never> { get }

}

public protocol BookmarkListInteracting: BookmarkStoring {
    
    var totalBookmarksCount: Int { get }

    func fetchRootBookmarksFolder() -> BookmarkEntity

    func fetchBookmarksInFolder(_: BookmarkEntity?) -> [BookmarkEntity]

    func deleteBookmark(_ bookmark: BookmarkEntity) throws -> [BookmarkEntity]

    func moveBookmark(_ bookmark: BookmarkEntity,
                      fromIndex: Int,
                      toIndex: Int) throws -> [BookmarkEntity]

}

public protocol FavoritesListInteracting: BookmarkStoring {

    func fetchFavorites() -> [BookmarkEntity]

    func deleteFavorite(_ favorite: BookmarkEntity) throws -> [BookmarkEntity]

    func moveFavorite(_ favorite: BookmarkEntity,
                      fromIndex: Int,
                      toIndex: Int) throws -> [BookmarkEntity]

}

public protocol MenuBookmarksInteracting {

    func createOrToggleFavorite(title: String, url: URL)
    
    func createBookmark(title: String, url: URL)
    func removeBookmark(for url: URL)
    
    func bookmark(for url: URL) -> BookmarkEntity?

}

public protocol EditBookmarkInteracting: BookmarkStoring {

    func fetchFolders() -> [BookmarkEntity]

    func save() throws

}


