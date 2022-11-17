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

public class FavoritesListViewModel: FavoritesListInteracting, ObservableObject {
    
    let context: NSManagedObjectContext

    public var favorites = [BookmarkEntity]()
    
    private let subject = PassthroughSubject<Void, Never>()
    public var externalUpdates: AnyPublisher<Void, Never>

    public var count: Int {
        favorites.count
    }

    public init(dbProvider: CoreDataDatabase) {
        self.externalUpdates = self.subject.eraseToAnyPublisher()
        
        self.context = dbProvider.makeContext(concurrencyType: .mainQueueConcurrencyType)
        refresh()
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
    
    private func refresh() {
        guard let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context) else {
            // Todo: error
            favorites = []
            return
        }
        
        favorites = favoritesFolder.favorites?.array as? [BookmarkEntity] ?? []
    }

    public func favorite(atIndex index: Int) -> BookmarkEntity? {
        guard favorites.indices.contains(index) else { return nil }
        return favorites[index]
    }

    public func removeFavorite(_ favorite: BookmarkEntity) {
        guard let favoriteFolder = favorite.favoriteFolder else {
            // ToDo: Pixel
            favorites = []
            return
        }

        favorite.removeFromFavorites()

        do {
            try context.save()
        } catch {
            context.rollback()
            // ToDo: Pixel
            #warning("error")
        }
        
        favorites = favoriteFolder.favorites?.array as? [BookmarkEntity] ?? []
    }
    
    public func moveFavorite(_ favorite: BookmarkEntity,
                             fromIndex: Int,
                             toIndex: Int) {
        guard let favoriteFolder = favorite.favoriteFolder else {
            // ToDo: Pixel
            favorites = []
            return
        }
        
        do {
            let mutableChildrenSet = favoriteFolder.mutableOrderedSetValue(forKeyPath: #keyPath(BookmarkEntity.favorites))
            
            mutableChildrenSet.moveObjects(at: IndexSet(integer: fromIndex), to: toIndex)
            
            try context.save()
        } catch {
            context.rollback()
            // ToDo: error with toast?
        }
        
        favorites = favoriteFolder.favorites?.array as? [BookmarkEntity] ?? []
    }

}
