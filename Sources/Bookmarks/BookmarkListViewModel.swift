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
            self?.bookmarks = self!.storage.fetchBookmarksInFolder(currentFolder)
        }
    }

}

public class CoreDataBookmarksLogic: BookmarkListInteracting {
    
    let context: NSManagedObjectContext
    
    public var updates: AnyPublisher<Void, Never>
    private let subject = PassthroughSubject<Void, Never>()
    
    init(context: NSManagedObjectContext) {
        self.context = context
        
        updates = subject
            .share() // share allows multiple subscribers
            .eraseToAnyPublisher() // we don't want to expose the concrete class to subscribers
    }
    
    // MARK: - Read

    public func fetchBookmarksInFolder(_ folder: BookmarkEntity?) -> [BookmarkEntity] {
        
        func queryFolder(_ folder: BookmarkEntity?) -> [BookmarkEntity] {
            let fetchRequest = NSFetchRequest<BookmarkEntity>(entityName: "BookmarkEntity")
            fetchRequest.returnsObjectsAsFaults = false
            if let folder = folder {
                fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.parent), folder)
            } else {
                fetchRequest.predicate = NSPredicate(format: "%K == nil", #keyPath(BookmarkEntity.parent))
            }
            
            do {
                return try context.fetch(fetchRequest)
            } catch {
                fatalError("Could not fetch Bookmarks")
            }
        }
        
        let bookmarks: [BookmarkEntity]
        if let folder = folder, let children = folder.children {
            if children.count > 20 {
                bookmarks = queryFolder(folder)
            } else {
                bookmarks = children.allObjects as! [BookmarkEntity]
            }
        } else {
            bookmarks = queryFolder(folder)
        }
        
        return bookmarks.sortedBookmarkEntities(using: .bookmarkAccessors)
    }

    public func deleteBookmark(_ bookmark: BookmarkEntity) throws {
        
        if let preceding = bookmark.previous {
            preceding.next = bookmark.next
        } else if let following = bookmark.next {
            following.previous = bookmark.previous
        }
        
        context.delete(bookmark)
        
        do {
            try context.save()
        } catch {
            context.rollback()
            // ToDo: Pixel
            throw error
        }
    }

    public func moveBookmarkInArray(_ array: [BookmarkEntity],
                                    fromIndex: Int,
                                    toIndex: Int) throws -> [BookmarkEntity] {
        do {
            let result = try array.movingBookmarkEntity(fromIndex: fromIndex,
                                                        toIndex: toIndex,
                                                        using: .bookmarkAccessors)
            
            try context.save()
            return result
        } catch {
            context.rollback()
            // ToDo: error with toast?
            return array
        }
    }
}
