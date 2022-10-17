//
//  BookmarksGenerator.swift
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
import Bookmarks
import CoreData
import XCTest

func tempDBDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

struct BasicBookmarksStructure {
    
    static let topLevelTitles = ["1", "Folder", "2", "3"]
    static let nestedTitles = ["Nested", "F1", "F2"]
    static let favoriteTitles = ["1", "2", "F1", "3"]
    
    static func createBookmarksList(usingNames names: [String], in context: NSManagedObjectContext) -> [BookmarkEntity] {
        
        var last: BookmarkEntity?
        let bookmarks: [BookmarkEntity] = names.map { name in
            let b = BookmarkEntity(context: context)
            b.uuid = UUID().uuidString
            b.title = name
            b.previous = last
            b.isFolder = false
            b.isFavorite = false
            last = b
            return b
        }
        return bookmarks
    }
    
    static func populateDB(context: NSManagedObjectContext) {
        
        // Structure:
        // Bookmark 1
        // Folder Folder ->
        //   - Folder Nested
        //   - Bookmark F1
        //   - Bookmark F2
        // Bookmark 2
        // Bookmark 3
        //
        // Favorites: 1 -> 2 -> F1 -> 3
        
        let topLevel = createBookmarksList(usingNames: topLevelTitles, in: context)
        
        let parent = topLevel[1]
        parent.isFolder = true
        
        let nestedLevel = createBookmarksList(usingNames: nestedTitles, in: context)
        for bookmark in nestedLevel {
            bookmark.parent = parent
        }
        
        nestedLevel[0].isFolder = true
        
        topLevel[0].isFavorite = true
        topLevel[2].isFavorite = true
        nestedLevel[1].isFavorite = true
        topLevel[3].isFavorite = true
        
        topLevel[0].nextFavorite = topLevel[2]
        topLevel[2].nextFavorite = nestedLevel[1]
        nestedLevel[1].nextFavorite = topLevel[3]
        
        do {
            try context.save()
        } catch {
            XCTFail("Couldn't populate db: \(error.localizedDescription)")
        }
    }
}
