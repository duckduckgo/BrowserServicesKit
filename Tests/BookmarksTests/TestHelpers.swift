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
    
    static func createBookmarksList(usingNames names: [String],
                                    parent: BookmarkEntity,
                                    in context: NSManagedObjectContext) -> [BookmarkEntity] {
        
        let bookmarks: [BookmarkEntity] = names.map { name in
            let b = BookmarkEntity(context: context)
            b.uuid = UUID().uuidString
            b.title = name
            b.isFolder = false
            b.isFavorite = false
            b.parent = parent
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
        
        do {
            try BookmarkUtils.prepareFoldersStructure(in: context)
        } catch {
            XCTFail("Couldn't populate base folders: \(error.localizedDescription)")
        }
        
        guard let rootFolder = BookmarkUtils.fetchRootFolder(context),
              let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context) else {
            XCTFail("Couldn't find required folders")
            return
        }
        
        let topLevel = createBookmarksList(usingNames: topLevelTitles, parent: rootFolder, in: context)
        
        let parent = topLevel[1]
        parent.isFolder = true
        
        let nestedLevel = createBookmarksList(usingNames: nestedTitles, parent: parent, in: context)
        
        nestedLevel[0].isFolder = true
        
        topLevel[0].isFavorite = true
        topLevel[2].isFavorite = true
        nestedLevel[1].isFavorite = true
        topLevel[3].isFavorite = true
        
        favoritesFolder.favorites = NSOrderedSet(array: [topLevel[0], topLevel[2], nestedLevel[1], topLevel[3]])
        
        do {
            try context.save()
        } catch {
            XCTFail("Couldn't populate db: \(error.localizedDescription)")
        }
    }
}
