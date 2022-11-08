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

public class BookmarkListViewModel: ObservableObject {

    let storage: BookmarkListInteracting
    var cancellable: AnyCancellable?

    public let currentFolder: BookmarkEntity?

    @Published public var bookmarks = [BookmarkEntity]()

    public init(storage: BookmarkListInteracting, currentFolder: BookmarkEntity?) {
        self.storage = storage
        self.currentFolder = currentFolder
        self.bookmarks = storage.fetchBookmarksInFolder(currentFolder)
        self.cancellable = self.storage.updates.sink { [weak self] in
            self?.refresh()
        }
    }

    public func bookmarkAt(_ index: Int) -> BookmarkEntity? {
        guard bookmarks.indices.contains(index) else { return nil }
        return bookmarks[index]
    }

    public func moveBookmark(_ bookmark: BookmarkEntity,
                             fromIndex: Int,
                             toIndex: Int) {
        do {
            bookmarks = try storage.moveBookmark(bookmark, fromIndex: fromIndex, toIndex: toIndex)
        } catch {
            // TODO pixel?
        }
    }

    public func deleteBookmark(_ bookmark: BookmarkEntity) {
        do {
            bookmarks = try storage.deleteBookmark(bookmark)
        } catch {
            // TODO pixel?
        }
    }

    public func viewModelForFolder(_ parent: BookmarkEntity) -> BookmarkListViewModel {
        return BookmarkListViewModel(storage: storage, currentFolder: parent)
    }

    public func refresh() {
        bookmarks = storage.fetchBookmarksInFolder(currentFolder)
    }

}

public class CoreDataBookmarksLogic: BookmarkListInteracting {
    
    let context: NSManagedObjectContext
    
    public var updates: AnyPublisher<Void, Never>
    private let subject = PassthroughSubject<Void, Never>()
    
    public init(context: NSManagedObjectContext) {
        self.context = context
        
        updates = subject
            .share() // share allows multiple subscribers
            .eraseToAnyPublisher() // we don't want to expose the concrete class to subscribers
    }
    
    // MARK: - Read

    public func fetchRootBookmarksFolder() -> BookmarkEntity {
        return BookmarkUtils.fetchRootFolder(context)!
    }

    private func fetchBookmarksInRootFolder() -> [BookmarkEntity] {
        guard let root = BookmarkUtils.fetchRootFolder(context) else {
            // Todo: error
            return []
        }
        
        // Todo: handle orphaned objects - here and in methods below
        return root.children?.array as? [BookmarkEntity] ?? []
    }

    public func fetchBookmarksInFolder(_ folder: BookmarkEntity?) -> [BookmarkEntity] {
        if folder == nil {
            return fetchBookmarksInRootFolder()
        } else {
            #warning("not optimal")
            folder?.managedObjectContext?.refreshAllObjects()
            return folder?.children?.array as? [BookmarkEntity] ?? []
        }
    }

    public func deleteBookmark(_ bookmark: BookmarkEntity) throws -> [BookmarkEntity] {
        guard let parentFolder = bookmark.parent else {
            // ToDo: Pixel
            return []
        }

        context.delete(bookmark)
        
        do {
            try context.save()
        } catch {
            context.rollback()
            // ToDo: Pixel
            throw error
        }

        return parentFolder.children?.array as? [BookmarkEntity] ?? []
    }

    public func moveBookmark(_ bookmark: BookmarkEntity,
                             fromIndex: Int,
                             toIndex: Int) throws -> [BookmarkEntity] {
        
        guard let parentFolder = bookmark.parent else {
            // ToDo: Pixel
            return []
        }
        
        do {
            
            let mutableChildrenSet = parentFolder.mutableOrderedSetValue(forKeyPath: #keyPath(BookmarkEntity.children))
            
            mutableChildrenSet.moveObjects(at: IndexSet(integer: fromIndex), to: toIndex)
            
            try context.save()
        } catch {
            context.rollback()
            // ToDo: error with toast?
        }
        
        return parentFolder.children?.array as? [BookmarkEntity] ?? []
    }
}
