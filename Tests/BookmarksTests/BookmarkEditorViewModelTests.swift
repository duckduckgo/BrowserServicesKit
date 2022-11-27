//
//  BookmarkEditorViewModelTests.swift
//  
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import XCTest
@testable import Bookmarks
import Persistence

class BookmarkEditorViewModelTests: XCTestCase {
    
    var db: CoreDataDatabase!
    
    override func setUpWithError() throws {
        
        let model = CoreDataDatabase.loadModel(from: Bundle.module, named: "BookmarksModel")!
        
        db = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: model)
        db.loadStore()
        
        let mainContext = db.makeContext(concurrencyType: .mainQueueConcurrencyType, name: "TestContext")
        BasicBookmarksStructure.populateDB(context: mainContext)
    }

    override func tearDownWithError() throws {
        try db.tearDown(deleteStores: true)
    }
    
    func testWhenCreatingFolderWithoutParentThenModelCanSave() {
        let model = BookmarkEditorViewModel(creatingFolderWithParentID: nil,
                                            bookmarksDatabase: db)
        
        XCTAssertFalse(model.canAddNewFolder)
        
        XCTAssertFalse(model.canSave)
        model.bookmark.title = "New"
        XCTAssert(model.canSave)
    }
    
    func testWhenCreatingFolderWithParentThenModelCanSave() {
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = BookmarkUtils.fetchRootFolder(context)
        XCTAssertNotNil(root)
        let model = BookmarkEditorViewModel(creatingFolderWithParentID: root?.objectID,
                                            bookmarksDatabase: db)
        
        XCTAssertFalse(model.canAddNewFolder)
        
        XCTAssertFalse(model.canSave)
        model.bookmark.title = "New"
        XCTAssert(model.canSave)
    }
    
    func testWhenEditingBookmarkThenModelCanSave() {
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = BookmarkUtils.fetchRootFolder(context)
        guard let firstBookmark = root?.childrenArray[0] else {
            XCTFail("Missing bookmark")
            return
        }
        
        XCTAssertFalse(firstBookmark.isFolder)
        
        let model = BookmarkEditorViewModel(editingEntityID: firstBookmark.objectID,
                                            bookmarksDatabase: db)
        
        XCTAssert(model.canAddNewFolder)
        XCTAssert(model.canSave)
    }
    
    func testWhenEditingFolderThenModelCanSave() {
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = BookmarkUtils.fetchRootFolder(context)
        guard let firstBookmark = root?.childrenArray[1] else {
            XCTFail("Missing bookmark")
            return
        }
        
        XCTAssert(firstBookmark.isFolder)
        
        let model = BookmarkEditorViewModel(editingEntityID: firstBookmark.objectID,
                                            bookmarksDatabase: db)
        
        XCTAssertFalse(model.canAddNewFolder)
        XCTAssert(model.canSave)
    }
    
    func testWhenEditingBookmarkThenFolderCanBeChanged() {
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = BookmarkUtils.fetchRootFolder(context)
        guard let firstBookmark = root?.childrenArray[0] else {
            XCTFail("Missing bookmark")
            return
        }
        
        XCTAssertFalse(firstBookmark.isFolder)
        
        let model = BookmarkEditorViewModel(editingEntityID: firstBookmark.objectID,
                                            bookmarksDatabase: db)
        
        let folders = model.locations
        
        let fetchFolders = BookmarkEntity.fetchRequest()
        fetchFolders.predicate = NSPredicate(format: "%K == true AND %K != %@", #keyPath(BookmarkEntity.isFolder),
                                                                                #keyPath(BookmarkEntity.uuid),
                                                                                BookmarkEntity.Constants.favoritesFolderID)
        let allFolders = (try? context.fetch(fetchFolders)) ?? []
        
        XCTAssertEqual(folders.count, allFolders.count)
    }
}
