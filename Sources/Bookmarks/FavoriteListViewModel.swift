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

    @Published public var favorites = [BookmarkEntity]()

    public var count: Int {
        favorites.count
    }

    public init(storage: FavoritesListInteracting) {
        self.storage = storage
        self.favorites = storage.fetchFavorites()
        self.cancellable = self.storage.updates.sink { [weak self] in
            self?.favorites = self!.storage.fetchFavorites()
        }
    }

    public func favorite(atIndex index: Int) -> BookmarkEntity? {
        guard favorites.indices.contains(index) else { return nil }
        return favorites[index]
    }

    public func delete(_ favorite: BookmarkEntity) {
        do {
            try storage.deleteFavorite(favorite)
        } catch {
            // TODO??
        }
    }

    public func move(_ favorite: BookmarkEntity, toIndex: Int) {
        guard let fromIndex = favorites.firstIndex(of: favorite) else { return }
        do {
            favorites = try storage.moveFavorite(favorite, fromIndex: fromIndex, toIndex: toIndex)
        } catch {
            // TODO??
        }
    }

}

public class CoreDataFavoritesLogic: FavoritesListInteracting {
    
    let context: NSManagedObjectContext
    
    public var updates: AnyPublisher<Void, Never>
    private let subject = PassthroughSubject<Void, Never>()
    
    public init(context: NSManagedObjectContext) {
        self.context = context
        
        updates = subject
            .share() // share allows multiple subscribers
            .eraseToAnyPublisher() // we don't want to expose the concrete class to subscribers
    }

    public func fetchFavorites() -> [BookmarkEntity] {

        guard let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context) else {
            // Todo: error
            return []
        }
        
        // Todo: add orphaned favorites
        return favoritesFolder.favorites?.array as? [BookmarkEntity] ?? []
    }
    
    public func deleteFavorite(_ favorite: BookmarkEntity) throws {
        
        context.delete(favorite)
        
        do {
            try context.save()
        } catch {
            context.rollback()
            // ToDo: Pixel
            throw error
        }
    }

    public func moveFavorite(_ favorite: BookmarkEntity,
                             fromIndex: Int,
                             toIndex: Int) throws -> [BookmarkEntity] {
        guard let favoriteFolder = favorite.favoriteFolder else {
            // ToDo: Pixel
            return []
        }
        
        do {
            let mutableChildrenSet = favoriteFolder.mutableOrderedSetValue(forKeyPath: #keyPath(BookmarkEntity.favorites))
            
            mutableChildrenSet.moveObjects(at: IndexSet(integer: fromIndex), to: toIndex)
            
            try context.save()
        } catch {
            context.rollback()
            // ToDo: error with toast?
        }
        
        return favoriteFolder.favorites?.array as? [BookmarkEntity] ?? []
    }
}

