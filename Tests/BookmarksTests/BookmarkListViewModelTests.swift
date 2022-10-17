//
//  BookmarkListViewModelTests.swift
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

import XCTest
import CoreData
import Common
import Persistence
@testable import Bookmarks
import BrowserServicesKit

class BookmarkListViewModelTests: XCTestCase {
    
    var db: CoreDataDatabase!
    
    static var tempDBDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func setUpWithError() throws {
        
        let model = CoreDataDatabase.loadModel(from: Bundle.module, named: "BookmarksModel")!
        
        db = CoreDataDatabase(name: "Test", containerLocation: Self.tempDBDir, model: model)
        db.loadStore()
    }

    override func tearDownWithError() throws {
        
    }
    
    
    let topLevelTitles = ["1", "Folder", "2", "3"]
    let nestedTitles = ["Nested", "F1", "F2"]
    let favoriteTitles = ["1", "2", "F1", "3"]
    
    func populateDB(context: NSManagedObjectContext) {
        
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
        
        var last: BookmarkEntity?
        let topLevel: [BookmarkEntity] = topLevelTitles.map { name in
            let b = BookmarkEntity(context: context)
            b.uuid = UUID().uuidString
            b.title = name
            b.previous = last
            b.isFolder = false
            b.isFavorite = false
            last = b
            return b
        }
        
        let parent = topLevel[1]
        parent.isFolder = true
        
        last = nil
        
        let nestedLevel: [BookmarkEntity] = nestedTitles.map { name in
            let b = BookmarkEntity(context: context)
            b.uuid = UUID().uuidString
            b.title = name
            b.parent = parent
            b.previous = last
            b.isFolder = false
            b.isFavorite = false
            last = b
            return b
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

    func testFetchingBookmarks() {
        let mainContext = db.makeContext(concurrencyType: .mainQueueConcurrencyType, name: "TestContext")
        
        populateDB(context: mainContext)
        
        let storage = CoreDataBookmarksStorage(context: db.makeContext(concurrencyType: .mainQueueConcurrencyType,
                                                                       name: "StorageContext"))
        
        let result = storage.fetchBookmarksInFolder(nil)
        
        let names = result.map { $0.title }
        XCTAssertEqual(names, topLevelTitles)
        
        let result2 = storage.fetchBookmarksInFolder(result[1])
        
        let names2 = result2.map { $0.title }
        XCTAssertEqual(names2, nestedTitles)
    }
    
    func testFetchingFavorites() {
        let mainContext = db.makeContext(concurrencyType: .mainQueueConcurrencyType, name: "TestContext")
        
        populateDB(context: mainContext)
        
        let storage = CoreDataBookmarksStorage(context: db.makeContext(concurrencyType: .mainQueueConcurrencyType,
                                                                       name: "StorageContext"))
        
        let result = storage.fetchFavorites()
        
        let names = result.map { $0.title }
        XCTAssertEqual(names, favoriteTitles)
    }
}
