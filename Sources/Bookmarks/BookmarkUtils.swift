//
//
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
import CoreData

public struct BookmarkUtils {
        
    public static func fetchRootFolder(_ context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), BookmarkEntity.Constants.rootFolderID)
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }

    public static func fetchFavoritesFolders(for displayMode: FavoritesDisplayMode, in context: NSManagedObjectContext) -> [BookmarkEntity] {
        displayMode.folderUUIDs.compactMap { fetchFavoritesFolder(withUUID: $0, in: context) }
    }

    public static func favoritesFoldersForUnfavoriting(of bookmark: BookmarkEntity, with displayMode: FavoritesDisplayMode) -> [BookmarkEntity] {
        // if displayAll - always remove from all
        // if displayNative:
        //   - if favorited on non-native: only remove from native
        //   - else remove from native and all
        let isFavoritedOnlyOnNativeFormFactor = Set(bookmark.favoriteFoldersSet.compactMap(\.uuid)) == displayMode.folderUUIDs

        if displayMode.isDisplayAll || isFavoritedOnlyOnNativeFormFactor {
            return Array(bookmark.favoriteFoldersSet)
        }
        return bookmark.favoriteFoldersSet.first(where: { $0.uuid == displayMode.nativePlatform.rawValue }).flatMap(Array.init) ?? []
    }

    public static func fetchFavoritesFolder(withUUID uuid: String, in context: NSManagedObjectContext) -> BookmarkEntity? {
        assert(BookmarkEntity.isValidFavoritesFolderID(uuid))
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), uuid)
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1

        return try? context.fetch(request).first
    }

    public static func fetchOrphanedEntities(_ context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "NOT %K IN %@ AND %K == NO AND %K == nil",
            #keyPath(BookmarkEntity.uuid),
            BookmarkEntity.Constants.favoriteFoldersIDs.union([BookmarkEntity.Constants.rootFolderID]),
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.parent)
        )
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(BookmarkEntity.uuid), ascending: true)]
        request.returnsObjectsAsFaults = false

        return (try? context.fetch(request)) ?? []
    }

    public static func prepareFoldersStructure(in context: NSManagedObjectContext) {

        if fetchRootFolder(context) == nil {
            insertRootFolder(uuid: BookmarkEntity.Constants.rootFolderID, into: context)
        }

        for uuid in BookmarkEntity.Constants.favoriteFoldersIDs {
            if fetchFavoritesFolder(withUUID: uuid, in: context) == nil {
                insertRootFolder(uuid: uuid, into: context)
            }
        }
    }

    public static func migrateToFormFactorSpecificFavorites(byCopyingExistingTo platform: FavoritesPlatform, in context: NSManagedObjectContext) {
        assert(platform != .all, "You must specify either desktop or mobile platform")

        guard let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(withUUID: BookmarkEntity.Constants.favoritesFolderID, in: context) else {
            return
        }

        if BookmarkUtils.fetchFavoritesFolder(withUUID: BookmarkEntity.Constants.desktopFavoritesFolderID, in: context) == nil {
            let desktopFavoritesFolder = insertRootFolder(uuid: BookmarkEntity.Constants.desktopFavoritesFolderID, into: context)

            if platform == .desktop {
                favoritesFolder.favoritesArray.forEach { bookmark in
                    bookmark.addToFavorites(folders: [desktopFavoritesFolder])
                }
            } else {
                desktopFavoritesFolder.shouldManageModifiedAt = false
            }
        }

        if BookmarkUtils.fetchFavoritesFolder(withUUID: BookmarkEntity.Constants.mobileFavoritesFolderID, in: context) == nil {
            let mobileFavoritesFolder = insertRootFolder(uuid: BookmarkEntity.Constants.mobileFavoritesFolderID, into: context)

            if platform == .mobile {
                favoritesFolder.favoritesArray.forEach { bookmark in
                    bookmark.addToFavorites(folders: [mobileFavoritesFolder])
                }
            } else {
                mobileFavoritesFolder.shouldManageModifiedAt = false
            }
        }
    }
    
    public static func fetchBookmark(for url: URL,
                                     predicate: NSPredicate = NSPredicate(value: true),
                                     context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        let urlPredicate = NSPredicate(format: "%K == %@ AND %K == NO",
                                       #keyPath(BookmarkEntity.url),
                                       url.absoluteString,
                                       #keyPath(BookmarkEntity.isPendingDeletion))
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [urlPredicate, predicate])
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }

    public static func fetchBookmarksPendingDeletion(_ context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == YES", #keyPath(BookmarkEntity.isPendingDeletion))

        return (try? context.fetch(request)) ?? []
    }

    public static func fetchModifiedBookmarks(_ context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K != nil", #keyPath(BookmarkEntity.modifiedAt))

        return (try? context.fetch(request)) ?? []
    }

    // MARK: Private

    @discardableResult
    private static func insertRootFolder(uuid: String, into context: NSManagedObjectContext) -> BookmarkEntity {
        let folder = BookmarkEntity(entity: BookmarkEntity.entity(in: context),
                                    insertInto: context)
        folder.uuid = uuid
        folder.title = uuid
        folder.isFolder = true

        return folder
    }
}
