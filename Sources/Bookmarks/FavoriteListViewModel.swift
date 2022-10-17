//
//  FavoritesListViewModel.swift
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

public class FavoritesListViewModel: ObservableObject {

    let storage: FavoritesListInteracting
    var cancellable: AnyCancellable?

    @Published public var favorties = [BookmarkEntity]()

     public init(storage: FavoritesListInteracting) {
        self.storage = storage
        self.favorties = storage.fetchFavorites()
        self.cancellable = self.storage.updates.sink { [weak self] in
            self?.favorties = self!.storage.fetchFavorites()
        }
    }

}

public class CoreDataFavoritesLogic: FavoritesListInteracting {
    
    let context: NSManagedObjectContext
    
    public var updates: AnyPublisher<Void, Never>
    private let subject = PassthroughSubject<Void, Never>()
    
    init(context: NSManagedObjectContext) {
        self.context = context
        
        updates = subject
            .share() // share allows multiple subscribers
            .eraseToAnyPublisher() // we don't want to expose the concrete class to subscribers
    }

    public func fetchFavorites() -> [BookmarkEntity] {

        let fetchRequest = NSFetchRequest<BookmarkEntity>(entityName: "BookmarkEntity")
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = NSPredicate(format: "%K == true", #keyPath(BookmarkEntity.isFavorite))
        
        do {
            let result = try context.fetch(fetchRequest)
            return result.sortedBookmarkEntities(using: .favoritesAccessors)
        } catch {
            fatalError("Could not fetch Favorites")
        }
    }
    
    public func deleteFavorite(_ favorite: BookmarkEntity) throws {
        
        if let preceding = favorite.previousFavorite {
            preceding.nextFavorite = favorite.nextFavorite
        } else if let following = favorite.nextFavorite {
            following.previousFavorite = favorite.previousFavorite
        }
        
        context.delete(favorite)
        
        do {
            try context.save()
        } catch {
            context.rollback()
            // ToDo: Pixel
            throw error
        }
    }

    public func moveFavoriteInArray(_ array: [BookmarkEntity],
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

