//
//  BookmarksProviderTests.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Bookmarks
import Common
import DDGSync
import Persistence
@testable import SyncDataProviders

internal class BookmarksProviderTests: BookmarksProviderTestsBase {

    func testThatLastSyncTimestampIsNilByDefault() {
        XCTAssertNil(provider.lastSyncTimestamp)
    }

    func testThatLastSyncTimestampIsPersisted() {
        provider.lastSyncTimestamp = "12345"
        XCTAssertEqual(provider.lastSyncTimestamp, "12345")
    }

    func testThatSentItemsAreProperlyCleanedUp() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)

            let bookmark1 = makeBookmark(named: "Bookmark 1", in: context)
            let bookmark2 = makeBookmark(in: context)

            let folder = makeFolder(named: "Folder", in: context)
            let bookmark3 = makeBookmark(withParent: folder, in: context)

            let bookmark4 = makeBookmark(named: "Bookmark 4", in: context)
            let bookmark5 = makeBookmark(named: "Bookmark 5", in: context)

            bookmark2.markPendingDeletion()
            folder.markPendingDeletion()

            do {
                try context.save()
            } catch {
                XCTFail("Failed to save context")
            }

            let sent = [bookmark1, bookmark2, bookmark3, bookmark4, bookmark5, folder].compactMap { try? Syncable(bookmark: $0, encryptedWith: crypter) }

            provider.cleanUpSentItems(sent, in: context)

            do {
                try context.save()
            } catch {
                XCTFail("Failed to save context")
            }

            let bookmarks = fetchAllNonRootEntities(in: context)

            XCTAssertEqual(bookmarks.count, 3)

            XCTAssertEqual(bookmarks[0].title, "Bookmark 1")
            XCTAssertEqual(bookmarks[1].title, "Bookmark 4")
            XCTAssertEqual(bookmarks[2].title, "Bookmark 5")

            XCTAssertEqual(bookmarks[0].modifiedAt, nil)
            XCTAssertEqual(bookmarks[1].modifiedAt, nil)
            XCTAssertEqual(bookmarks[2].modifiedAt, nil)
        }
    }
}
