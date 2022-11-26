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
    var mainContext: NSManagedObjectContext!
    
    override func setUpWithError() throws {
        
        let model = CoreDataDatabase.loadModel(from: Bundle.module, named: "BookmarksModel")!
        
        db = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: model)
        db.loadStore()
        
        self.mainContext = db.makeContext(concurrencyType: .mainQueueConcurrencyType, name: "TestContext")
        BasicBookmarksStructure.populateDB(context: mainContext)
    }

    override func tearDownWithError() throws {
        mainContext.reset()
        mainContext = nil
        
        try db.tearDown(deleteStores: true)
    }

    func testWhenFolderIsSetThenBookmarksFetchedFromThatLocation() {
        
        let viewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                              parentID: nil)
        XCTAssertEqual(viewModel.currentFolder, BookmarkUtils.fetchRootFolder(viewModel.context))
        let result = viewModel.bookmarks
        
        XCTAssertEqual(result[1], viewModel.bookmark(at: 1))
        
        let names = result.map { $0.title }
        XCTAssertEqual(names, BasicBookmarksStructure.topLevelTitles)
        
        let nestedViewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                                    parentID: result[1].objectID)
        XCTAssertEqual(nestedViewModel.currentFolder?.objectID, result[1].objectID)
        
        let result2 = nestedViewModel.bookmarks
        
        let names2 = result2.map { $0.title }
        XCTAssertEqual(names2, BasicBookmarksStructure.nestedTitles)
    }
        
    func testWhenDeletingABookmarkItIsRemoved() {
        
        let viewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                              parentID: nil)
        let result = viewModel.bookmarks
        let idSet = Set(result.map { $0.objectID })
        
        let bookmark = result[0]
        XCTAssertFalse(bookmark.isFolder)
        
        viewModel.deleteBookmark(bookmark)
        
        let newViewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                               parentID: nil)
        let newResult = newViewModel.bookmarks
        let newIdSet = Set(newResult.map { $0.objectID })
        
        let diff = idSet.subtracting(newIdSet)
        
        XCTAssertEqual(diff.count, 1)
        XCTAssert(diff.contains(bookmark.objectID))
    }
    
    func testWhenDeletingABookmarkFolderItIsRemovedWithContents() {
        
        let viewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                              parentID: nil)
        let result = viewModel.bookmarks
        let idSet = Set(result.map { $0.objectID })
        
        let folder = result[1]
        XCTAssert(folder.isFolder)
        
        let totalCount = viewModel.totalBookmarksCount
        let expectedCountAfterRemoval = totalCount - folder.childrenArray.count - 1
        
        viewModel.deleteBookmark(folder)
        
        let newViewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                               parentID: nil)
        let newResult = newViewModel.bookmarks
        let newIdSet = Set(newResult.map { $0.objectID })
        
        let diff = idSet.subtracting(newIdSet)
        
        XCTAssertEqual(diff.count, 1)
        XCTAssertEqual(newViewModel.totalBookmarksCount, expectedCountAfterRemoval)
        XCTAssert(diff.contains(folder.objectID))
    }
    
    func testWhenMovingBookmarkItGoesToNewPosition() {
        
        let viewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                              parentID: nil)
        let result = viewModel.bookmarks
        
        let first = result[0]
        let second = result[1]
        
        viewModel.moveBookmark(first,
                               fromIndex: 0,
                               toIndex: 1)
        
        let newViewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                               parentID: nil)
        let newResult = newViewModel.bookmarks
        let newFirst = newResult[0]
        let newSecond = newResult[1]
        
        XCTAssertEqual(first.objectID, newSecond.objectID)
        XCTAssertEqual(second.objectID, newFirst.objectID)
        XCTAssertEqual(result.count, newResult.count)
    }
    
    func testWhenUsingWrongIndexesNothingHappens() {
        
        let viewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                              parentID: nil)
        let result = viewModel.bookmarks
        
        let first = result[0]
        let second = result[1]
        
        // Wrong indexes
        viewModel.moveBookmark(first,
                               fromIndex: 1,
                               toIndex: 0)
        
        // Out of bounds `from`
        viewModel.moveBookmark(first,
                               fromIndex: 10,
                               toIndex: 1)
        
        // Out of bounds `to`
        viewModel.moveBookmark(first,
                               fromIndex: 0,
                               toIndex: 10)
        
        let newViewModel = BookmarkListViewModel(bookmarksDatabase: db,
                                                 parentID: nil)
        let newResult = newViewModel.bookmarks
        let newFirst = newResult[0]
        let newSecond = newResult[1]
        
        XCTAssertEqual(first.objectID, newFirst.objectID)
        XCTAssertEqual(second.objectID, newSecond.objectID)
        XCTAssertEqual(result.count, newResult.count)
    }
}
