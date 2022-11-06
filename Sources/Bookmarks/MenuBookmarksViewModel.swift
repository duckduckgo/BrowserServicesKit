//
//  MenuBookmarksViewModel.swift
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

import Foundation
import CoreData

class MenuBookmarksViewModel: MenuBookmarksInteracting {
    
    let context: NSManagedObjectContext
    
    lazy var rootFolder: BookmarkEntity! = BookmarkUtils.fetchRootFolder(context)
    lazy var favoritesFolder: BookmarkEntity! = BookmarkUtils.fetchFavoritesFolder(context)
    
    init(viewContext: NSManagedObjectContext) {
        self.context = viewContext
    }
    
    private func save() {
        do {
            try context.save()
        } catch {
            // ToDo: Error
            context.rollback()
        }
    }
    
    func createOrToggleFavorite(title: String, url: URL) {
        if let bookmark = BookmarkUtils.fetchBookmark(for: url, context: context) {
            if bookmark.isFavorite {
                bookmark.isFavorite = false
                bookmark.favoriteFolder = nil
            } else {
                bookmark.isFavorite = true
                bookmark.favoriteFolder = favoritesFolder
            }
        } else {
            let favorite = BookmarkEntity.makeBookmark(title: title,
                                                       url: url.absoluteString,
                                                       parent: rootFolder,
                                                       context: context)
            favorite.isFavorite = true
            favorite.favoriteFolder = favoritesFolder
        }
        
        save()
    }
    
    func createBookmark(title: String, url: URL) {
        let favorite = BookmarkEntity.makeBookmark(title: title,
                                                   url: url.absoluteString,
                                                   parent: rootFolder,
                                                   context: context)
        save()
    }
    
    func removeBookmark(for url: URL) {
        if let bookmark = BookmarkUtils.fetchBookmark(for: url, context: context) {
            context.delete(bookmark)
            save()
        }
    }
    
    func bookmark(for url: URL) -> BookmarkEntity? {
        BookmarkUtils.fetchBookmark(for: url, context: context)
    }
    
}
