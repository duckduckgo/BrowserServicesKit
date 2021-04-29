//
//  SuggestionLoadingTests.swift
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
@testable import BrowserServicesKit

final class SuggestionLoadingTests: XCTestCase {

    class SuggestionLoadingDataSourceMock: SuggestionLoadingDataSource {
        private var bookmarks = [Bookmark]()

        private var completionData: Data?
        private var completionError: Error?

        private var asyncDelay: TimeInterval?

        private(set) var bookmarkCallCount = 0
        private(set) var dataCallCount = 0

        init(data: Data? = nil, error: Error? = nil, bookmarks: [Bookmark] = [], delay: TimeInterval? = nil) {
            self.completionData = data
            self.bookmarks = bookmarks
            self.completionError = error
            self.asyncDelay = delay
        }

        func bookmarks(for suggestionLoading: SuggestionLoading) -> [Bookmark] {
            bookmarkCallCount += 1
            return bookmarks
        }

        func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                               suggestionDataFromUrl url: URL,
                               withParameters parameters: [String : String],
                               completion: @escaping (Data?, Error?) -> Void) {
            dataCallCount += 1
            if let asyncDelay = asyncDelay {
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(asyncDelay * 1000))) {
                    completion(self.completionData, self.completionError)
                }
            } else {
                completion(completionData, completionError)
            }
        }
    }

    struct E: Error {}

    func testWhenNoDataSource_ThenErrorMustBeReturned() {
        let loader = SuggestionLoader(urlFactory: nil)
        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (suggestions, error) in
            XCTAssertNil(suggestions)
            XCTAssertNotNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenQueryIsEmpty_ThenSuggestionsAreEmpty() {
        let dataSource = SuggestionLoadingDataSourceMock()
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "", maximum: 10) { (suggestions, error) in
            XCTAssertEqual(suggestions, [])
            XCTAssertNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenQueryHasOneLetter_ThenSuggestionsLoadedWithoutBookmarks() {
        let dataSource = SuggestionLoadingDataSourceMock(data: Data.anAPIResultData, bookmarks: BookmarkMock.someBookmarks)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "a", maximum: 10) { (suggestions, error) in
            XCTAssertEqual(suggestions?.count, APIResult.anAPIResult.items.count)
            XCTAssertNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenGetSuggestionsIsCalled_ThenDataSourceAsksForBookmarksAndDataOnce() {
        let dataSource = SuggestionLoadingDataSourceMock(data: Data.anAPIResultData, bookmarks: BookmarkMock.someBookmarks)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (_, _) in
            XCTAssertEqual(dataSource.bookmarkCallCount, 1)
            XCTAssertEqual(dataSource.dataCallCount, 1)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testMaximumNumberOfSuggestions() {
        let dataSource = SuggestionLoadingDataSourceMock(data: Data.anAPIResultData, bookmarks: BookmarkMock.someBookmarks)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 2) { (suggestions, _) in
            XCTAssertEqual(suggestions?.count, 2)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenQueryMatchesBookmarkTitle_thenBookmarkMustBeSuggested() {
        let dataSource = SuggestionLoadingDataSourceMock(data: Data.anAPIResultData, bookmarks: BookmarkMock.someBookmarks)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test 1", maximum: 10) { (suggestions, _) in
            XCTAssert(suggestions!.contains(Suggestion(bookmark: BookmarkMock.someBookmarks[0])))
            XCTAssertFalse(suggestions!.contains(Suggestion(bookmark: BookmarkMock.someBookmarks[1])))
            XCTAssertFalse(suggestions!.contains(Suggestion(bookmark: BookmarkMock.someBookmarks[2])))
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenMaximumNumberIsLargeEnough_ThenSuggestionsContainAllRemoteSuggestionsAndTwoBookmarkSuggestions() {
        let dataSource = SuggestionLoadingDataSourceMock(data: Data.anAPIResultData, bookmarks: BookmarkMock.someBookmarks)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (suggestions, _) in
            XCTAssertEqual(suggestions?.count, 5)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenAPIReturnsError_ThenBookmarksSuggested() {
        let dataSource = SuggestionLoadingDataSourceMock(error: E(), bookmarks: BookmarkMock.someBookmarks, delay: 0)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (suggestions, error) in
            XCTAssertEqual(suggestions?.count, 2)
            XCTAssertNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenAPIReturnsMalformedData_ThenBookmarksSuggested() {
        let dataSource = SuggestionLoadingDataSourceMock(data: "malformed data".data(using: .utf8),
                                                         bookmarks: BookmarkMock.someBookmarks,
                                                         delay: 0)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (suggestions, error) in
            XCTAssertEqual(suggestions?.count, 2)
            XCTAssertNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenAPIReturnsErrorAndNoBookmarks_ThenFailedToLoadErrorReturned() {
        let dataSource = SuggestionLoadingDataSourceMock(error: E(), bookmarks: [], delay: 0)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (suggestions, error) in
            XCTAssertNil(suggestions)
            XCTAssertTrue(error as? SuggestionLoader.SuggestionLoaderError == .failedToObtainData)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenAPIReturnsMalformedDataAndNoBookmarks_ThenFailedToLoadErrorReturned() {
        let dataSource = SuggestionLoadingDataSourceMock(data: "malformed data".data(using: .utf8), bookmarks: [], delay: 0)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (suggestions, error) in
            XCTAssertNil(suggestions)
            XCTAssertTrue(error as? SuggestionLoader.SuggestionLoaderError == .failedToObtainData)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenAPIReturnsErrorButHasResults_ThenSuggestionsAreReturned() {
        let dataSource = SuggestionLoadingDataSourceMock(data: Data.anAPIResultData,
                                                         error: E(),
                                                         bookmarks: BookmarkMock.someBookmarks,
                                                         delay: 0)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (suggestions, error) in
            XCTAssertEqual(suggestions?.count, 5)
            XCTAssertNil(error)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenAPIReturnsAfterDelay_ThenSuggestionsContainAllRemoteSuggestionsAndTwoBookmarkSuggestions() {
        let dataSource = SuggestionLoadingDataSourceMock(data: Data.anAPIResultData, bookmarks: BookmarkMock.someBookmarks, delay: 0.2)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (suggestions, error) in
            XCTAssertEqual(suggestions?.count, 5)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testWhenAPIReturnsErrorAfterDelay_ThenSuggestionsContainTwoBookmarkSuggestions() {
        let dataSource = SuggestionLoadingDataSourceMock(error: E(), bookmarks: BookmarkMock.someBookmarks, delay: 0.2)
        let loader = SuggestionLoader(dataSource: dataSource, urlFactory: nil)

        let e = expectation(description: "suggestions callback")
        loader.getSuggestions(query: "test", maximum: 10) { (suggestions, error) in
            XCTAssertEqual(suggestions?.count, 2)
            e.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

}

extension BookmarkMock {

    static var someBookmarks: [Bookmark] {
        [ BookmarkMock(url: URL(string: "duckduckgo.com")!, title: "Test 1", isFavorite: true),
          BookmarkMock(url: URL(string: "spreadprivacy.com")!, title: "Test 2", isFavorite: true),
          BookmarkMock(url: URL(string: "wikipedia.org")!, title: "Wikipedia", isFavorite: false) ]
    }

}

extension APIResult {

    static var anAPIResult: APIResult {
        var result = APIResult()
        result.items = [
            [ "phrase": "Test" ],
            [ "phrase": "Test 2" ],
            [ "phrase": "Unrelated" ]
        ]
        return result
    }

}

extension Data {

    static var anAPIResultData: Data {
        let encoder = JSONEncoder()

        // swiftlint:disable force_try
        return try! encoder.encode(APIResult.anAPIResult.items)
        // swiftlint:enable force_try
    }

}
