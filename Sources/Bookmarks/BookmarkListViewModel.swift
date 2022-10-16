//
//  BookmarkListViewModel.swift
//  

import Foundation
import Combine
import CoreData

public class BookmarkListViewModel: ObservableObject {

    let storage: WritableBookmarkStoring
    var cancellable: AnyCancellable?

    public let parent: Bookmark?

    @Published public var bookmarks = [Bookmark]()

     public init(factory: BookmarkStorageFactory = InMemoryBookmarkStorageFactory(), parent: Bookmark?) {
        self.storage = factory.makeWriteableStorage()
        self.parent = parent
        self.bookmarks = storage.fetchBookmarksInFolder(parent)
        self.cancellable = self.storage.updates.sink { [weak self] in
            self?.bookmarks = self!.storage.fetchBookmarksInFolder(parent)
        }
    }

}

extension BookmarkEntity: Bookmark {
    public var parent: Bookmark? {
        get {
            parentEntity
        }
        set {
            if let entity = newValue as? BookmarkEntity {
                parentEntity = entity
            }
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
    
    //
    
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

    public func fetchBookmarksInFolder(_ bookmark: Bookmark?) -> [Bookmark] {
        
        let fetchRequest = NSFetchRequest<BookmarkEntity>(entityName: "BookmarkEntity")
        fetchRequest.returnsObjectsAsFaults = false
        if let bookmark = bookmark, let parent = bookmark as? BookmarkEntity {
            fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.parentEntity), parent)
        } else {
            fetchRequest.predicate = NSPredicate(format: "%K == nil", #keyPath(BookmarkEntity.parentEntity))
        }
        
        do {
            let result = try context.fetch(fetchRequest)
            
            return sorted(result, keyPath: \.next)
        } catch {
            fatalError("Could not fetch Bookmarks")
        }
    }

    public func fetchFavorites() -> [Bookmark] {

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
    
    //
    
    public func deleteBookmark(_ bookmark: Bookmark) {
        // To refactor, as mutation should be transactional and unpolluted. Either:
        //   - separate worker for mutation
        //   - DB provider in init ?
        guard let entity = bookmark as? BookmarkEntity else {
            fatalError("Bookmark is not an Entity")
        }
        
        context.delete(entity)
        do {
            try context.save()
        } catch {
            // ToDo: Pixel
            fatalError("Cannot into DB :( \(error)")
        }
    }

    /// after can be nil to be at the start of the list
    public func moveBookmark(_ bookmark: Bookmark, after newPreceding: Bookmark?) {
        // Todo: change api to Array based? Reason: typical mutation on Linked Lists is based on a head/tail pointers which we don't have here.
        
    }
    
    public func save() async {
        // Do we need this?
    }
}

/// Poor implementation just to hook up the UI.
/// I'm assuming no rollback required as we'll just "discard" the storage instance if we don't want to commit it.
public class InMemoryBookmarkStorageFactory: BookmarkStorageFactory, WritableBookmarkStoring {

    public var updates: AnyPublisher<Void, Never>

    private let subject = PassthroughSubject<Void, Never>()
    private var bookmarks = [ConcreteBookmark]()

    public init() {
        updates = subject
            .share() // share allows multiple subscribers
            .eraseToAnyPublisher() // we don't want to expose the concrete class to subscribers
    }

    public func deleteBookmark(_ bookmark: Bookmark) {
        bookmarks = bookmarks.filter { (bookmark as? ConcreteBookmark) != $0 }
    }

    public func moveBookmark(_ bookmark: Bookmark, after: Bookmark?) {
        guard let concrete = bookmark as? ConcreteBookmark else { return }
        if after == nil {
            if let index = bookmarks.firstIndex(of: concrete) {
                bookmarks.remove(at: index)
            }
            bookmarks.insert(concrete, at: 0)
        }
    }

    public func fetchBookmarksInFolder(_ parent: Bookmark?) -> [Bookmark] {
        if let parent = parent as? ConcreteBookmark {
            return parent.children
        }
        return bookmarks
    }

    public func fetchFavorites() -> [Bookmark] {
        var favorites = [Bookmark]()
        findFavorites(inFolder: bookmarks, addingTo: &favorites)
        return favorites
    }

    private func findFavorites(inFolder folder: [ConcreteBookmark], addingTo favorites: inout [Bookmark]) {
        folder.forEach {
            // This code technically allows favorites to be folders

            if $0.isFavorite {
                favorites.append($0)
            }

            if $0.isFolder {
                findFavorites(inFolder: $0.children, addingTo: &favorites)
            }
        }
    }

    public func save() async {
        Task { // simulates async nature of
            try await Task.sleep(nanoseconds: 1_000_000_000 / 10) // 1/10 of a second

            /// Changes were made so send an update
            subject.send()
        }
    }

    public func makeReadOnlyStorage() -> BookmarkStoring {
        self
    }

    public func makeWriteableStorage() -> WritableBookmarkStoring {
        self
    }

    class ConcreteBookmark: Bookmark, Equatable {

        static func == (lhs: InMemoryBookmarkStorageFactory.ConcreteBookmark, rhs: InMemoryBookmarkStorageFactory.ConcreteBookmark) -> Bool {
            lhs.id == rhs.id
        }

        let id: UUID

        var parent: Bookmark?

        var title: String?

        var url: String?

        var isFavorite: Bool

        var isFolder: Bool

        var children = [ConcreteBookmark]()

        init(id: UUID, isFolder: Bool, parent: Bookmark? = nil, title: String? = nil, url: String? = nil, isFavorite: Bool = false) {
            self.id = id
            self.isFolder = isFolder
            self.parent = parent
            self.title = title
            self.url = url
            self.isFavorite = isFavorite
        }

    }

}
