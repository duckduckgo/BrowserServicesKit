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

    public static func fetchFavoritesFolder(_ context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), BookmarkEntity.Constants.favoritesFolderID)
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }

    public static func fetchOrphanedEntities(_ context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "NOT %K IN %@ AND %K == NO",
            #keyPath(BookmarkEntity.uuid),
            [BookmarkEntity.Constants.rootFolderID, BookmarkEntity.Constants.favoritesFolderID],
            #keyPath(BookmarkEntity.isFolder)
        )
        request.returnsObjectsAsFaults = false

        return (try? context.fetch(request)) ?? []
    }

    public static func prepareFoldersStructure(in context: NSManagedObjectContext) {
        
        func insertRootFolder(uuid: String, into context: NSManagedObjectContext) {
            let folder = BookmarkEntity(entity: BookmarkEntity.entity(in: context),
                                        insertInto: context)
            folder.uuid = uuid
            folder.title = uuid
            folder.isFolder = true
        }
        
        if fetchRootFolder(context) == nil {
            insertRootFolder(uuid: BookmarkEntity.Constants.rootFolderID, into: context)
        }
        
        if fetchFavoritesFolder(context) == nil {
            insertRootFolder(uuid: BookmarkEntity.Constants.favoritesFolderID, into: context)
        }
    }
    
    public static func fetchBookmark(for url: URL,
                                     predicate: NSPredicate = NSPredicate(value: true),
                                     context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        let urlPredicate = NSPredicate(format: "%K == %@ AND %K == NO", #keyPath(BookmarkEntity.url), url.absoluteString, #keyPath(BookmarkEntity.isPendingDeletion))
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
}
