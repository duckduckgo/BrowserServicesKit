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
    
    init(database: CoreDataDatabase) {
        self.context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
    }
    
    public func importBookmarks(_ bookmarks: [BookmarkOrFolder]) async throws {
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            
            context.performAndWait { () -> Void in
                do {
                    guard let topLevelBookmarksFolder = BookmarkUtils.fetchRootFolder(context),
                    let topLevelFavoritesFolder = BookmarkUtils.fetchFavoritesFolder(context) else {
                        throw BookmarksCoreDataStorageError.fetchingExistingItemFailed
                    }
                    
                    try recursivelyCreateEntities(from: bookmarks,
                                                  parent: topLevelBookmarksFolder,
                                                  favorites: topLevelFavoritesFolder)
                } catch {
                    continuation.resume(throwing: error)
                }
                continuation.resume()
            }
        }
    }

    private func recursivelyCreateEntities(from bookmarks: [BookmarkOrFolder],
                                           parent: BookmarkEntity,
                                           favorites: BookmarkEntity) throws {
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
                                                  favorites: favorites)
                }
            case .favorite:
                break
//                if let url = bookmarkOrFolder.url {
//                    if let bookmark = containsBookmark(with: url) {
//                        // TodDo - mark as fav
//                    } else {
//                        let newFavorite = BookmarkEntity.makeBookmark(title: bookmarkOrFolder.name,
//                                                                      url: url.absoluteString,
//                                                                      parent: parent,
//                                                                      context: context)
//                        // TodDo - mark as fav
//                    }
//                }
            case .bookmark:
                break
//                if let url = bookmarkOrFolder.url {
//                    if parent == topLevelBookmarksFolder,
//                       containsBookmark(url: url, searchType: .topLevelBookmarksOnly, parentId: parent.objectID) {
//                        continue
//                    } else {
//                        _ = try saveNewBookmark(withTitle: bookmarkOrFolder.name, url: url, parentID: parent.objectID)
//                    }
//                }
            }
        }
    }
    
    private func containsBookmark(with url: URL) -> Bool {
        return false
    }
}

