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
import Common
import Persistence

public class MenuBookmarksViewModel: MenuBookmarksInteracting {
    
    let context: NSManagedObjectContext
    
    private var _rootFolder: BookmarkEntity?
    private var rootFolder: BookmarkEntity? {
        if _rootFolder == nil {
            _rootFolder = BookmarkUtils.fetchRootFolder(context)
            
            if _rootFolder == nil {
                errorEvents?.fire(.fetchingRootItemFailed(.menu))
            }
        }
        return _rootFolder
    }
    
    private var _favoritesFolder: BookmarkEntity?
    private var favoritesFolder: BookmarkEntity?{
        if _favoritesFolder == nil {
            _favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context)
            
            if _favoritesFolder == nil {
                errorEvents?.fire(.fetchingRootItemFailed(.menu))
            }
        }
        return _favoritesFolder
    }
    
    private let errorEvents: EventMapping<BookmarksModelError>?
    
    public init(bookmarksDatabase: CoreDataDatabase,
                errorEvents: EventMapping<BookmarksModelError>? = nil) {
        self.errorEvents = errorEvents
        self.context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
        registerForChanges()
    }

    private func registerForChanges() {
        NotificationCenter.default.addObserver(forName: NSManagedObjectContext.didSaveObjectsNotification,
                                               object: nil,
                                               queue: .main) { [weak self] notification in
            guard let otherContext = notification.object as? NSManagedObjectContext,
                  otherContext != self?.context,
            otherContext.persistentStoreCoordinator == self?.context.persistentStoreCoordinator else { return }

            self?.context.mergeChanges(fromContextDidSave: notification)
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            context.rollback()
            errorEvents?.fire(.saveFailed(.menu))
        }
    }
    
    public func createOrToggleFavorite(title: String, url: URL) {
        guard let favoritesFolder = favoritesFolder,
              let rootFolder = rootFolder else {
            return
        }
        
        if let bookmark = BookmarkUtils.fetchBookmark(for: url, context: context) {
            if bookmark.isFavorite {
                bookmark.removeFromFavorites()
            } else {
                bookmark.addToFavorites(favoritesRoot: favoritesFolder)
            }
        } else {
            let favorite = BookmarkEntity.makeBookmark(title: title,
                                                       url: url.absoluteString,
                                                       parent: rootFolder,
                                                       context: context)
            favorite.addToFavorites(favoritesRoot: favoritesFolder)
        }
        
        save()
    }
    
    public func createBookmark(title: String, url: URL) {
        guard let rootFolder = rootFolder else {
            return
        }
        _ = BookmarkEntity.makeBookmark(title: title,
                                        url: url.absoluteString,
                                        parent: rootFolder,
                                        context: context)
        save()
    }
    
    public func removeBookmark(for url: URL) {
        if let bookmark = BookmarkUtils.fetchBookmark(for: url, context: context) {
            context.delete(bookmark)
            save()
        }
    }
    
    public func bookmark(for url: URL) -> BookmarkEntity? {
        BookmarkUtils.fetchBookmark(for: url, context: context)
    }
    
}
