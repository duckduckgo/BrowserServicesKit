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

    private var observer: NSObjectProtocol?
    private let subject = PassthroughSubject<Void, Never>()
    private let localSubject = PassthroughSubject<Void, Never>()
    public var externalUpdates: AnyPublisher<Void, Never>
    public var localUpdates: AnyPublisher<Void, Never>

    private let errorEvents: EventMapping<BookmarksModelError>?
    
    public init(bookmarksDatabase: CoreDataDatabase,
                parentID: NSManagedObjectID?,
                errorEvents: EventMapping<BookmarksModelError>?) {
        self.externalUpdates = self.subject.eraseToAnyPublisher()
        self.localUpdates = self.localSubject.eraseToAnyPublisher()
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
                self?.refresh()
                self?.subject.send()
            }
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

    private func reattachOrphanedBookmarks(forMoving bookmark: BookmarkEntity, toIndex: Int) {
        guard let rootFolder = BookmarkUtils.fetchRootFolder(context) else {
            return
        }
        let orphanedBookmarks: [BookmarkEntity] = BookmarkUtils.fetchOrphanedEntities(context)
        guard !orphanedBookmarks.isEmpty else {
            return
        }
        let orphanedBookmarksToAttachToRootFolder: [BookmarkEntity] = {
            let toIndexInOrphanedBookmarks = toIndex - rootFolder.childrenArray.count
            guard bookmark.parent == nil else {
                return Array(orphanedBookmarks.prefix(through: toIndexInOrphanedBookmarks))
            }
            guard let bookmarkIndexInOrphans = orphanedBookmarks.firstIndex(where: { $0.uuid == bookmark.uuid }) else {
                return [bookmark]
            }
            return Array(orphanedBookmarks.prefix(through: max(toIndexInOrphanedBookmarks, bookmarkIndexInOrphans)))
        }()
        orphanedBookmarksToAttachToRootFolder.forEach { rootFolder.addToChildren($0) }
    }

    public func moveBookmark(_ bookmark: BookmarkEntity,
                             fromIndex: Int,
                             toIndex: Int) {
        let shouldIncludeOrphans = bookmark.parent?.uuid == BookmarkEntity.Constants.rootFolderID || bookmark.parent == nil
        if shouldIncludeOrphans {
            reattachOrphanedBookmarks(forMoving: bookmark, toIndex: toIndex)
        }

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
        refresh()
    }

    public func softDeleteBookmark(_ bookmark: BookmarkEntity) {
        if bookmark.parent == nil {
            BookmarkUtils.fetchRootFolder(context)?.addToChildren(bookmark)
        }
        guard bookmark.parent != nil else {
            errorEvents?.fire(.missingParent(.bookmark))
            return
        }

        bookmark.markPendingDeletion()

        save()
        refresh()
    }

    public func reloadData() {
        context.performAndWait {
            self.refresh()
        }
    }

    private func refresh() {
        bookmarks = fetchBookmarksInFolder(currentFolder)
    }

    private func save() {
        do {
            try context.save()
            localSubject.send()
        } catch {
            context.rollback()
            errorEvents?.fire(.saveFailed(.bookmarks), error: error)
        }
    }
    
    // MARK: - Read

    public func countBookmarksForDomain(_ domain: String) -> Int {
        let count = countBookmarksForDomain(domain, inFolder: fetchRootBookmarksFolder())
        return count
    }

    private func countBookmarksForDomain(_ domain: String, inFolder folder: BookmarkEntity) -> Int {
        var count = 0
        folder.childrenArray.forEach { child in
            if child.isFolder {
                count += countBookmarksForDomain(domain, inFolder: child)
            } else if child.urlObject?.isPart(ofDomain: domain) == true {
                count += 1
            }
        }
        return count
    }

    public var totalBookmarksCount: Int {
        let countRequest = BookmarkEntity.fetchRequest()
        countRequest.predicate = NSPredicate(format: "%K == false && %K == NO", #keyPath(BookmarkEntity.isFolder), #keyPath(BookmarkEntity.isPendingDeletion))
        
        return (try? context.count(for: countRequest)) ?? 0
    }

    private func fetchRootBookmarksFolder() -> BookmarkEntity {
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
        let shouldFetchRootFolder = folder == nil || folder?.uuid == BookmarkEntity.Constants.rootFolderID

        var folderBookmarks: [BookmarkEntity] = {
            if let folder = folder {
                return folder.childrenArray
            }
            return fetchBookmarksInRootFolder()
        }()

        if shouldFetchRootFolder {
            let orphanedBookmarks = BookmarkUtils.fetchOrphanedEntities(context)
            folderBookmarks += orphanedBookmarks
        }
        return folderBookmarks
    }

    public func bookmark(with id: NSManagedObjectID) -> BookmarkEntity? {
        return (try? context.existingObject(with: id)) as? BookmarkEntity
    }

}
