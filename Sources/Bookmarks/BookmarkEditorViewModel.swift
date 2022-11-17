//
//  BookmarkEditorViewModel.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public class BookmarkEditorViewModel: ObservableObject {

    public struct Location {

        public let bookmark: BookmarkEntity?
        public let depth: Int

    }

    let context: NSManagedObjectContext

    @Published public var bookmark: BookmarkEntity
    @Published public var locations = [Location]()

    lazy var favoritesFolder: BookmarkEntity! = BookmarkUtils.fetchFavoritesFolder(context)

    public var canSave: Bool {
        let titleOK = bookmark.title?.trimmingWhitespace().count ?? 0 > 0
        let urlOK = bookmark.isFolder ? true : bookmark.urlObject != nil
        return titleOK && urlOK
    }

    public var canAddNewFolder: Bool {
        !bookmark.isFolder
    }

    public var isNew: Bool {
        bookmark.isInserted
    }

    public init(dbProvider: CoreDataDatabase,
                editingEntityID: NSManagedObjectID?,
                parentFolderID: NSManagedObjectID?) {
        
        self.context = dbProvider.makeContext(concurrencyType: .mainQueueConcurrencyType)

        let editingEntity: BookmarkEntity
        if let editingEntityID = editingEntityID {
            guard let entity = context.object(with: editingEntityID) as? BookmarkEntity else {
                fatalError("Failed to load entity when expected")
            }
            editingEntity = entity
        } else {

            let parent: BookmarkEntity?
            if let parentFolderID = parentFolderID {
                parent = context.object(with: parentFolderID) as? BookmarkEntity
            } else {
                parent = BookmarkUtils.fetchRootFolder(context)
            }
            assert(parent != nil)

            // We don't support creating bookmarks from scratch at this time, so it must be a folder
            editingEntity = BookmarkEntity.makeFolder(title: "",
                                                      parent: parent!,
                                                      context: context)
        }
        self.bookmark = editingEntity

        refresh()
    }

    public func refresh() {
        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        var locations = [Location(bookmark: rootFolder, depth: 0)]

        func descendInto(_ folders: [BookmarkEntity], depth: Int) {
            folders.forEach { entity in
                if entity.isFolder,                    
                    entity.uuid != bookmark.uuid
                {
                    locations.append(Location(bookmark: entity, depth: depth))
                    descendInto(entity.childrenArray, depth: depth + 1)
                }
            }
        }

        descendInto(rootFolder.childrenArray, depth: 1)

        self.locations = locations
    }

    public func selectLocationAtIndex(_ index: Int) {
        guard locations.indices.contains(index) else { return }
        guard let newParent = locations[index].bookmark else { return }
        bookmark.parent = newParent
        refresh()
    }

    public func isSelected(_ folder: BookmarkEntity?) -> Bool {
        return bookmark.parent?.uuid == (folder?.uuid ?? BookmarkEntity.Constants.rootFolderID)
    }

    public func removeFromFavorites() {
        assert(bookmark.isFavorite)
        bookmark.removeFromFavorites()
    }

    public func addToFavorites() {
        assert(!bookmark.isFavorite)
        bookmark.addToFavorites(favoritesRoot: favoritesFolder)
    }

    public func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("\(error)")
        }
    }
}
