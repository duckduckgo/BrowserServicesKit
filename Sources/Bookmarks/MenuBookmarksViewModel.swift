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

    private var observer: NSObjectProtocol?
    
    private let errorEvents: EventMapping<BookmarksModelError>?
    
    public init(bookmarksDatabase: CoreDataDatabase,
                errorEvents: EventMapping<BookmarksModelError>?) {
        self.errorEvents = errorEvents
        self.context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
        registerForChanges()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func registerForChanges() {
        observer = NotificationCenter.default.addObserver(forName: NSManagedObjectContext.didSaveObjectsNotification,
                                                          object: nil,
                                                          queue: nil) { [weak self] notification in
            guard let otherContext = notification.object as? NSManagedObjectContext,
                  otherContext != self?.context,
            otherContext.persistentStoreCoordinator == self?.context.persistentStoreCoordinator else { return }

            self?.context.perform {
                self?.context.mergeChanges(fromContextDidSave: notification)
                self?.context.refreshAllObjects()
            }
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            context.rollback()
            errorEvents?.fire(.saveFailed(.menu), error: error)
        }
    }
    
    public func createOrToggleFavorite(title: String, url: URL) {
        guard let favoritesFolder = favoritesFolder,
              let rootFolder = rootFolder else {
            return
        }
        
        let queriedBookmark = favorite(for: url) ?? bookmark(for: url)
        
        if let bookmark = queriedBookmark {
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
    
    public func favorite(for url: URL) -> BookmarkEntity? {
        BookmarkUtils.fetchBookmark(for: url,
                                    predicate: NSPredicate(format: "%K == true AND %K == NO", #keyPath(BookmarkEntity.isFavorite), #keyPath(BookmarkEntity.isPendingDeletion)),
                                    context: context)
    }
    
    public func bookmark(for url: URL) -> BookmarkEntity? {
        BookmarkUtils.fetchBookmark(for: url, context: context)
    }
    
}
