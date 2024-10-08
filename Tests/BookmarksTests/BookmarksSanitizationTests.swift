//
//  BookmarksSanitizationTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import CoreData
import Foundation

final class BookmarksSanitizationTests: XCTestCase {

    private var bookmarksDatabase: CoreDataDatabase!
    private var location: URL!
    private var context: NSManagedObjectContext!
    private var rootFolder: BookmarkEntity!

    override func setUp() {
        super.setUp()

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: location, model: model)
        bookmarksDatabase.loadStore()

        context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        rootFolder = BookmarkUtils.fetchRootFolder(context)
    }

    override func tearDown() {
        super.tearDown()

        try? FileManager.default.removeItem(at: location)
    }

    func testRunsCustomSanitization() {
        let bookmark = stubBookmark(url: "some.url", in: context)
        var didRunCustomFunction = false
        let sanitization = BookmarkSanitization.custom { _ in
            didRunCustomFunction = true
        }

        sanitization.sanitize(bookmark)

        XCTAssertTrue(didRunCustomFunction)
    }

    func testNavigationalSanitizationAddsSchemeToURL() {
        let bookmark = stubBookmark(url: "some.url", in: context)
        let sanitization = BookmarkSanitization.navigational

        sanitization.sanitize(bookmark)

        XCTAssertEqual(bookmark.url, "http://some.url")
    }

    func testNavigationalSanitizationAllowsIPAddress() {
        let bookmark = stubBookmark(url: "192.168.1.1", in: context)
        let sanitization = BookmarkSanitization.navigational

        sanitization.sanitize(bookmark)

        XCTAssertEqual(bookmark.url, "http://192.168.1.1")
    }

    func testNavigationalSanitizationKeepsExistingHTTPScheme() {
        let bookmark = stubBookmark(url: "https://some.url", in: context)
        let sanitization = BookmarkSanitization.navigational

        sanitization.sanitize(bookmark)

        XCTAssertEqual(bookmark.url, "https://some.url")
    }

    func testNavigationalSanitizationKeepsExistingScheme() {
        let bookmark = stubBookmark(url: "somescheme://some.url", in: context)
        let sanitization = BookmarkSanitization.navigational

        sanitization.sanitize(bookmark)

        XCTAssertEqual(bookmark.url, "somescheme://some.url")
    }

    func testNavigationalSanitizationUsesPunycodeForEmoji() {
        let bookmark = stubBookmark(url: "https://😍.url", in: context)
        let sanitization = BookmarkSanitization.navigational

        sanitization.sanitize(bookmark)

        XCTAssertEqual(bookmark.url, "https://xn--r28h.url")
    }

    func testNavigationalSanitizationKeepsEmptyString() {
        let bookmark = stubBookmark(url: "  ", in: context)
        let sanitization = BookmarkSanitization.navigational

        sanitization.sanitize(bookmark)

        XCTAssertEqual(bookmark.url, "  ")
    }

    private func stubBookmark(url: String, in context: NSManagedObjectContext) -> BookmarkEntity {
        BookmarkEntity.makeBookmark(title: "", url: url, parent: rootFolder, context: context)
    }
}
