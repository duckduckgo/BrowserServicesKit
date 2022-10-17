//
//  BookmarkListViewModel.swift
//  

import Foundation
import Combine
import CoreData
import Persistence

public class BookmarkListViewModel: ObservableObject {

    let storage: WritableBookmarkStoring
    var cancellable: AnyCancellable?

    public let currentFolder: BookmarkEntity?

    @Published public var bookmarks = [BookmarkEntity]()

     public init(storage: WritableBookmarkStoring, currentFolder: BookmarkEntity?) {
        self.storage = storage
        self.currentFolder = currentFolder
        self.bookmarks = storage.fetchBookmarksInFolder(currentFolder)
        self.cancellable = self.storage.updates.sink { [weak self] in
            self?.bookmarks = self!.storage.fetchBookmarksInFolder(currentFolder)
        }
    }

}

public class CoreDataBookmarksStorage: WritableBookmarkStoring {
    
    let contextFactory: ManagedObjectContextFactory
    let context: NSManagedObjectContext
    
    public var updates: AnyPublisher<Void, Never>
    private let subject = PassthroughSubject<Void, Never>()
    
    init(contextFactory: ManagedObjectContextFactory,
         context: NSManagedObjectContext? = nil) {
        self.contextFactory = contextFactory
        self.context = context ?? contextFactory.makeContext(concurrencyType: .mainQueueConcurrencyType,
                                                             name: "Bookmarks Storage Context")
        
        updates = subject
            .share() // share allows multiple subscribers
            .eraseToAnyPublisher() // we don't want to expose the concrete class to subscribers
    }
    
    // MARK: - Read
    
    func sorted(_ array: [BookmarkEntity], keyPath: KeyPath<BookmarkEntity, BookmarkEntity?>) -> [BookmarkEntity] {
        guard let first = array.first(where: { $0.previous == nil }) else {
            // TODO: pixel
            return array
        }
        
        var sorted = [first]
        sorted.reserveCapacity(array.count)
        
        var current = first[keyPath: keyPath]
        while let next = current {
            sorted.append(next)
            current = next[keyPath: keyPath]
        }
        
        return sorted
    }

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
        
        return sorted(bookmarks, keyPath: \.next)
    }

    public func fetchFavorites() -> [BookmarkEntity] {

        let fetchRequest = NSFetchRequest<BookmarkEntity>(entityName: "BookmarkEntity")
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = NSPredicate(format: "%K == true", #keyPath(BookmarkEntity.isFavorite))
        
        do {
            let result = try context.fetch(fetchRequest)
            return sorted(result, keyPath: \.nextFavorite)
        } catch {
            fatalError("Could not fetch Favorites")
        }
    }
    
    // MARK: - Write
    
    public func deleteBookmark(_ bookmark: BookmarkEntity) {
        
        let writable = contextFactory.makeContext(concurrencyType: .mainQueueConcurrencyType,
                                                  name: "Bookmarks Storing")
        do {
            try writable.existingObject(with: bookmark.objectID)
            try writable.save()
        } catch {
            // ToDo: Pixel
            fatalError("Cannot into DB :( \(error)")
        }
    }

    public func moveBookmarkInArray(_ array: [BookmarkEntity],
                                    fromIndex: Int,
                                    toIndex: Int) -> [BookmarkEntity] {
        do {
            return try array.movingBookmark(fromIndex: fromIndex,
                                            toIndex: toIndex,
                                            orderAccessors: BookmarkEntity.bookmarkOrdering)
        } catch {
            // ToDo
            return []
        }
    }
    
    public func save() async {
        // Do we need this?
    }
}
