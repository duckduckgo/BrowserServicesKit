//
//  BookmarkCoreDataImporter.swift
//  
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Persistence

public class BookmarkCoreDataImporter {
    
    let context: NSManagedObjectContext
    
    public init(database: CoreDataDatabase) {
        self.context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
    }
    
    public func importBookmarks(_ bookmarks: [BookmarkOrFolder]) async throws {
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            
            context.performAndWait { () -> Void in
                do {
                    guard let topLevelBookmarksFolder = BookmarkUtils.fetchRootFolder(context),
                    let topLevelFavoritesFolder = BookmarkUtils.fetchFavoritesFolder(context) else {
                        throw BookmarksCoreDataError.fetchingExistingItemFailed
                    }
                    
                    var existingBookmarkURLs = try allExistingBookmarkURLs(in: context)
                    
                    try recursivelyCreateEntities(from: bookmarks,
                                                  parent: topLevelBookmarksFolder,
                                                  favoritesRoot: topLevelFavoritesFolder,
                                                  existingBookmarkURLs: &existingBookmarkURLs)
                    try context.save()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func allExistingBookmarkURLs(in context: NSManagedObjectContext) throws -> Set<String> {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "BookmarkEntity")
        fetch.predicate = NSPredicate(format: "%K == false", #keyPath(BookmarkEntity.isFolder))
        fetch.resultType = .dictionaryResultType
        fetch.propertiesToFetch = [#keyPath(BookmarkEntity.url)]
        
        let dict = try context.fetch(fetch) as? [Dictionary<String, Any>]
        
        if let result = dict?.compactMap({ $0.first?.value as? String }) {
            return Set(result)
        }
        return []
    }

    private func recursivelyCreateEntities(from bookmarks: [BookmarkOrFolder],
                                           parent: BookmarkEntity,
                                           favoritesRoot: BookmarkEntity,
                                           existingBookmarkURLs: inout Set<String>) throws {
        for bookmarkOrFolder in bookmarks {
            if bookmarkOrFolder.isInvalidBookmark {
                continue
            }

            switch bookmarkOrFolder.type {
            case .folder:
                let folder = BookmarkEntity.makeFolder(title: bookmarkOrFolder.name,
                                                       parent: parent,
                                                       context: context)
                if let children = bookmarkOrFolder.children {
                    try recursivelyCreateEntities(from: children,
                                                  parent: folder,
                                                  favoritesRoot: favoritesRoot,
                                                  existingBookmarkURLs: &existingBookmarkURLs)
                }
            case .favorite:
                if let url = bookmarkOrFolder.url {
                    if existingBookmarkURLs.contains(url.absoluteString),
                       let bookmark = BookmarkUtils.fetchBookmark(for: url, context: context) {
                        bookmark.addToFavorites(favoritesRoot: favoritesRoot)
                    } else {
                        let newFavorite = BookmarkEntity.makeBookmark(title: bookmarkOrFolder.name,
                                                                      url: url.absoluteString,
                                                                      parent: parent,
                                                                      context: context)
                        newFavorite.addToFavorites(favoritesRoot: favoritesRoot)
                        existingBookmarkURLs.insert(url.absoluteString)
                    }
                }
            case .bookmark:
                if let url = bookmarkOrFolder.url {
                    if parent.isRoot,
                       parent.childrenArray.first(where: { $0.urlObject == url }) != nil {
                        continue
                    } else {
                        _ = BookmarkEntity.makeBookmark(title: bookmarkOrFolder.name,
                                                        url: url.absoluteString,
                                                        parent: parent,
                                                        context: context)
                        existingBookmarkURLs.insert(url.absoluteString)
                    }
                }
            }
        }
    }
    
    private func containsBookmark(with url: URL) -> Bool {
        return false
    }
}

