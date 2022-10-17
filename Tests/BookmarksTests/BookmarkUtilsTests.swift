//
//  BookmarkUtilsTests.swift
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
import Persistence
@testable import Bookmarks

class BookmarkUtilsTests: XCTestCase {

    var db: CoreDataDatabase!
    
    override func setUpWithError() throws {
        
        let model = CoreDataDatabase.loadModel(from: Bundle.module, named: "BookmarksModel")!
        
        db = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: model)
        db.loadStore()
    }

    override func tearDownWithError() throws {
        try db.tearDown(deleteStores: true)
    }

    func testMovingBookmarks() {
        
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType, name: "Test")
        
        let orderedNames = ["1", "2", "3", "4"]
        
        let bookmarks = BasicBookmarksStructure.createBookmarksList(usingNames: orderedNames, in: context)
        
        var ordered = bookmarks.movingBookmark(fromIndex: 2,
                                               toIndex: 1,
                                               orderAccessors: BookmarkEntity.bookmarkOrdering)
        
        XCTAssertEqual(ordered.map { $0.title }, ["1", "3", "2", "4"])
        
        ordered = bookmarks.movingBookmark(fromIndex: 3,
                                               toIndex: 2,
                                               orderAccessors: BookmarkEntity.bookmarkOrdering)
        
        XCTAssertEqual(ordered.map { $0.title }, ["1", "2", "4", "3"])
        
        ordered = bookmarks.movingBookmark(fromIndex: 0,
                                               toIndex: 3,
                                               orderAccessors: BookmarkEntity.bookmarkOrdering)
        
        XCTAssertEqual(ordered.map { $0.title }, ["2", "3", "4", "1"])
    }
}
