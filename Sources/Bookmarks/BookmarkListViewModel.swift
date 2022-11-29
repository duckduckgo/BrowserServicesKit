//
//  BookmarkListViewModel.swift
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
import Combine
import Common
import CoreData
import Persistence

public class BookmarkListViewModel: BookmarkListInteracting, ObservableObject {

    public let currentFolder: BookmarkEntity?
    
    let context: NSManagedObjectContext
    
    public var bookmarks = [BookmarkEntity]()
    
    private let subject = PassthroughSubject<Void, Never>()
    public var externalUpdates: AnyPublisher<Void, Never>
    
    private let errorEvents: EventMapping<BookmarksModelError>?
    
    public init(bookmarksDatabase: CoreDataDatabase,
                parentID: NSManagedObjectID?,
                errorEvents: EventMapping<BookmarksModelError>?) {
        self.externalUpdates = self.subject.eraseToAnyPublisher()
        self.errorEvents = errorEvents
        self.context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)

        if let parentID = parentID {
            if let bookmark = (try? context.existingObject(with: parentID)) as? BookmarkEntity {
                if bookmark.isFolder {
                    self.currentFolder = bookmark
                } else {
                    errorEvents?.fire(.bookmarkFolderExpected)
                    self.currentFolder = BookmarkUtils.fetchRootFolder(context)
                }
            } else {
                // This is possible with Sync and specific timing.
                errorEvents?.fire(.bookmarksListMissingFolder)
                self.currentFolder = BookmarkUtils.fetchRootFolder(context)
            }
        } else {
            self.currentFolder = BookmarkUtils.fetchRootFolder(context)
        }

        self.bookmarks = fetchBookmarksInFolder(currentFolder)
        
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
            self?.refresh()
            self?.subject.send()
        }
    }

    public func bookmark(at index: Int) -> BookmarkEntity? {
        guard bookmarks.indices.contains(index) else { return nil }
        return bookmarks[index]
    }

    public func toggleFavorite(_ bookmark: BookmarkEntity) {
        if bookmark.isFavorite {
            bookmark.removeFromFavorites()
        } else if let folder = BookmarkUtils.fetchFavoritesFolder(context) {
            bookmark.addToFavorites(favoritesRoot: folder)
        }
        save()
    }

    public func moveBookmark(_ bookmark: BookmarkEntity,
                             fromIndex: Int,
                             toIndex: Int) {
        guard let parentFolder = bookmark.parent else {
            errorEvents?.fire(.missingParent(.bookmark))
            return
        }
        
        guard let children = parentFolder.children,
              fromIndex < children.count,
              toIndex < children.count else {
            errorEvents?.fire(.indexOutOfRange(.bookmarks))
            return
        }
        
        guard let actualBookmark = children[fromIndex] as? BookmarkEntity,
              actualBookmark == bookmark else {
            errorEvents?.fire(.bookmarksListIndexNotMatchingBookmark)
            return
        }

        let mutableChildrenSet = parentFolder.mutableOrderedSetValue(forKeyPath: #keyPath(BookmarkEntity.children))
        mutableChildrenSet.moveObjects(at: IndexSet(integer: fromIndex), to: toIndex)

        save()

        bookmarks = parentFolder.childrenArray
    }

    public func deleteBookmark(_ bookmark: BookmarkEntity) {
        guard let parentFolder = bookmark.parent else {
            errorEvents?.fire(.missingParent(.bookmark))
            return
        }

        context.delete(bookmark)

        save()

        bookmarks = parentFolder.childrenArray
    }

    private func refresh() {
        bookmarks = fetchBookmarksInFolder(currentFolder)
    }

    private func save() {
        do {
            try context.save()
        } catch {
            context.rollback()
            errorEvents?.fire(.saveFailed(.bookmarks), error: error)
        }
    }
    
    // MARK: - Read
    
    public var totalBookmarksCount: Int {
        let countRequest = BookmarkEntity.fetchRequest()
        countRequest.predicate = NSPredicate(value: true)
        
        return (try? context.count(for: countRequest)) ?? 0
    }

    public func fetchRootBookmarksFolder() -> BookmarkEntity {
        return BookmarkUtils.fetchRootFolder(context)!
    }

    private func fetchBookmarksInRootFolder() -> [BookmarkEntity] {
        guard let root = BookmarkUtils.fetchRootFolder(context) else {
            errorEvents?.fire(.fetchingRootItemFailed(.bookmarks))
            return []
        }
        
        return root.childrenArray
    }

    public func fetchBookmarksInFolder(_ folder: BookmarkEntity?) -> [BookmarkEntity] {
        if let folder = folder {
            return folder.childrenArray
        } else {
            return fetchBookmarksInRootFolder()
        }
    }

    public func bookmark(with id: NSManagedObjectID) -> BookmarkEntity? {
        return (try? context.existingObject(with: id)) as? BookmarkEntity
    }

}
