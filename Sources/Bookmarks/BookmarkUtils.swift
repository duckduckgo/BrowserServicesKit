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
        
        do {
            return try context.fetch(request).first
        } catch {
            fatalError("Could not fetch Bookmarks")
        }
    }
    
    public static func fetchFavoritesFolder(_ context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), BookmarkEntity.Constants.favoritesFolderID)
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            fatalError("Could not fetch Bookmarks")
        }
    }
    
    public static func prepareFoldersStructure(in context: NSManagedObjectContext) throws {
        
        func insertRootFolder(uuid: String, into context: NSManagedObjectContext) throws {
            let folder = BookmarkEntity(context: context)
            folder.uuid = uuid
            folder.isFolder = true
        }
        
        if fetchRootFolder(context) == nil {
            try insertRootFolder(uuid: BookmarkEntity.Constants.rootFolderID, into: context)
        }
        
        if fetchFavoritesFolder(context) == nil {
            try insertRootFolder(uuid: BookmarkEntity.Constants.favoritesFolderID, into: context)
        }
    }
    
    public static func fetchBookmark(for url: URL, context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.url), url.absoluteString)
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            fatalError("Could not fetch Bookmark")
        }
    }
}
