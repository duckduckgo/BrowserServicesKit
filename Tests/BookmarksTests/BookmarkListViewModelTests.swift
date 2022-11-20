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
    
    override func setUpWithError() throws {
        
        let model = CoreDataDatabase.loadModel(from: Bundle.module, named: "BookmarksModel")!
        
        db = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: model)
        db.loadStore()
    }

    override func tearDownWithError() throws {
        try db.tearDown(deleteStores: true)
    }

    func testFetchingBookmarks() {
        let mainContext = db.makeContext(concurrencyType: .mainQueueConcurrencyType, name: "TestContext")
        
        BasicBookmarksStructure.populateDB(context: mainContext)
        
        let viewModel = BookmarkListViewModel(bookmarksDatabaseStack: db,
                                              parentID: nil)
        let result = viewModel.bookmarks
        
        let names = result.map { $0.title }
        XCTAssertEqual(names, BasicBookmarksStructure.topLevelTitles)
        
        let nestedViewModel = BookmarkListViewModel(bookmarksDatabaseStack: db,
                                                    parentID: result[1].objectID)
        
        let result2 = nestedViewModel.bookmarks
        
        let names2 = result2.map { $0.title }
        XCTAssertEqual(names2, BasicBookmarksStructure.nestedTitles)
    }
    
}
