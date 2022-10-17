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
        // To refactor, as mutation should be transactional and unpolluted. Either:
        //   - separate worker for mutation
        //   - DB provider in init ?
        context.delete(bookmark)
        do {
            try context.save()
        } catch {
            // ToDo: Pixel
            fatalError("Cannot into DB :( \(error)")
        }
    }

    public func moveBookmarkInArray(_ array: [BookmarkEntity],
                                    fromIndex: Int,
                                    toIndex: Int) -> [BookmarkEntity] {
        guard fromIndex < array.count, toIndex < array.count else {
            // ToDo: Pixel
            return array
        }
        
        var result = array
        let bookmark = result.remove(at: fromIndex)
        result.insert(bookmark, at: toIndex)
        
        // Remove from list
        if let preceding = bookmark.previous {
            preceding.next = bookmark.next
        } else if let following = bookmark.next {
            following.previous = bookmark.previous
        }
        
        // Insert in new place
        let newPreceding: BookmarkEntity? = toIndex > 0 ? result[toIndex - 1] : nil
        let newFollowing: BookmarkEntity? = toIndex + 1 < result.count ? result[toIndex + 1] : nil
        
        bookmark.previous = newPreceding
        bookmark.next = newFollowing
        
        return result
    }
    
    public func save() async {
        // Do we need this?
    }
}
