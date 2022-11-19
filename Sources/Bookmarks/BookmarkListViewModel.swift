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
import CoreData
import Persistence

public class BookmarkListViewModel: BookmarkListInteracting, ObservableObject {

    public let currentFolder: BookmarkEntity?
    
    let context: NSManagedObjectContext
    
    public var bookmarks = [BookmarkEntity]()
    
    private let subject = PassthroughSubject<Void, Never>()
    public var externalUpdates: AnyPublisher<Void, Never>
    
    public init(bookmarksDatabaseStack: CoreDataDatabase, parentID: NSManagedObjectID?) {
        self.externalUpdates = self.subject.eraseToAnyPublisher()
        
        self.context = bookmarksDatabaseStack.makeContext(concurrencyType: .mainQueueConcurrencyType)

        if let parentID = parentID {
            self.currentFolder = context.object(with: parentID) as? BookmarkEntity
        } else {
            self.currentFolder = BookmarkUtils.fetchRootFolder(context)
        }

        guard (currentFolder?.isFolder ?? true) else {
            fatalError("Folder expected")
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

    public func bookmarkAt(_ index: Int) -> BookmarkEntity? {
        guard bookmarks.indices.contains(index) else { return nil }
        return bookmarks[index]
    }

    public func moveBookmark(_ bookmark: BookmarkEntity,
                             fromIndex: Int,
                             toIndex: Int) {
        guard let parentFolder = bookmark.parent else {
            // ToDo: Pixel
            bookmarks = []
            return
        }
        
        do {
            
            let mutableChildrenSet = parentFolder.mutableOrderedSetValue(forKeyPath: #keyPath(BookmarkEntity.children))
            
            mutableChildrenSet.moveObjects(at: IndexSet(integer: fromIndex), to: toIndex)
            
            try context.save()
        } catch {
            context.rollback()
            #warning("Handle this")
        }
        
        bookmarks = parentFolder.childrenArray
    }

    public func deleteBookmark(_ bookmark: BookmarkEntity) {
        guard let parentFolder = bookmark.parent else {
            // ToDo: Pixel
            bookmarks = []
            return
        }

        context.delete(bookmark)
        
        do {
            try context.save()
        } catch {
            context.rollback()
            #warning("Handle this")
        }

        bookmarks = parentFolder.childrenArray
    }

    public func refresh() {
        bookmarks = fetchBookmarksInFolder(currentFolder)
    }
    
    public func getTotalBookmarksCount() -> Int {
        totalBookmarksCount
    }

    public var hasFavorites: Bool {
        bookmarks.contains(where: { $0.isFavorite })
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
            // Todo: error
            return []
        }
        
        // Todo: handle orphaned objects - here and in methods below
        return root.childrenArray
    }

    public func fetchBookmarksInFolder(_ folder: BookmarkEntity?) -> [BookmarkEntity] {
        if let folder = folder {
#warning("not optimal")
            folder.managedObjectContext?.refreshAllObjects()
            return folder.childrenArray
        } else {
            return fetchBookmarksInRootFolder()
        }
    }

}
