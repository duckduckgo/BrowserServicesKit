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

struct BookmarkUtils {
    
    public enum Constants {
        public static let rootFolderID = "root_folder"
        public static let favoritesFolderID = "favorites_folder"
    }
        
    public static func fetchRootFolder(_ context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = NSFetchRequest<BookmarkEntity>(entityName: "BookmarkEntity")
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), Constants.rootFolderID)
        request.returnsObjectsAsFaults = false
        
        do {
            return try context.fetch(request).first
        } catch {
            fatalError("Could not fetch Bookmarks")
        }
    }
    
    public static func fetchFavoritesFolder(_ context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = NSFetchRequest<BookmarkEntity>(entityName: "BookmarkEntity")
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), Constants.favoritesFolderID)
        request.returnsObjectsAsFaults = false
        
        do {
            return try context.fetch(request).first
        } catch {
            fatalError("Could not fetch Bookmarks")
        }
    }
}
