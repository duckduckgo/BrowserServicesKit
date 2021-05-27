//
//  SuggestionTests.swift
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

final class SuggestionTests: XCTestCase {

    func testSuggestionInitializedFromBookmark() {
        let url = URL(string: "duckduckgo.com")!
        let title = "DuckDuckGo"
        let isFavorite = true
        let bookmarkMock = BookmarkMock(url: url, title: title, isFavorite: isFavorite)
        let suggestion = Suggestion(bookmark: bookmarkMock)

        XCTAssertEqual(suggestion, Suggestion.bookmark(title: title, url: url, isFavorite: isFavorite))
    }

    func testWhenSuggestionKeyIsPhrase_ThenSuggestionIsPhrase() {
        let key = Suggestion.phraseKey
        let phraseValue = "value"
        let suggestion = Suggestion(key: key, value: phraseValue)

        XCTAssertEqual(suggestion, Suggestion.phrase(phrase: phraseValue))
    }

    func testWhenSuggestionKeyIsNotPhrase_ThenSuggestionIsUnknown() {
        let key = "Key"
        let value = "value"
        let suggestion = Suggestion(key: key, value: value)

        XCTAssertEqual(suggestion, Suggestion.unknown(value: value))
    }

    func testWhenUrlIsAccessed_ThenOnlySuggestionsThatContainUrlReturnsIt() {
        let url = URL(string: "https://www.duckduckgo.com")!

        var phraseSuggestion = Suggestion.phrase(phrase: "phrase")
        var websiteSuggestion = Suggestion.website(url: url)
        var bookmarkSuggestion = Suggestion.bookmark(title: "Title", url: url, isFavorite: true)
        var historyEntrySuggestion = Suggestion.historyEntry(title: "Title", url: url)
        var unknownSuggestion = Suggestion.unknown(value: "phrase")

        XCTAssertNil(phraseSuggestion.url)
        XCTAssertEqual(websiteSuggestion.url, url)
        XCTAssertEqual(bookmarkSuggestion.url, url)
        XCTAssertEqual(historyEntrySuggestion.url, url)
        XCTAssertNil(phraseSuggestion.url)
    }

    func testWhenTitleIsAccessed_ThenOnlySuggestionsThatContainUrlStoreIt() {
        let url = URL(string: "https://www.duckduckgo.com")!
        let title = "Original Title"

        var phraseSuggestion = Suggestion.phrase(phrase: "phrase")
        var websiteSuggestion = Suggestion.website(url: url)
        var bookmarkSuggestion = Suggestion.bookmark(title: title, url: url, isFavorite: true)
        var historyEntrySuggestion = Suggestion.historyEntry(title: title, url: url)
        var unknownSuggestion = Suggestion.unknown(value: "phrase")

        XCTAssertNil(phraseSuggestion.title)
        XCTAssertNil(websiteSuggestion.title)
        XCTAssertEqual(bookmarkSuggestion.title, title)
        XCTAssertEqual(historyEntrySuggestion.title, title)
        XCTAssertNil(phraseSuggestion.title)
    }

    func testWhenInitFromHistoryEntry_ThenHistroryEntrySuggestionIsInitialized() {
        let url = URL(string: "https://www.duckduckgo.com")!
        let title = "Title"


        let historyEntry = HistoryEntryMock(identifier: UUID(), url: url, title: title, numberOfVisits: 1, lastVisit: Date())
        let suggestion = Suggestion(historyEntry: historyEntry)

        guard case .historyEntry = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(suggestion.url, url)
        XCTAssertEqual(suggestion.title, title)
    }

    func testWhenInitFromBookmark_ThenBookmarkSuggestionIsInitialized() {
        let url = URL(string: "https://www.duckduckgo.com")!
        let title = "Title"


        let bookmark = BookmarkMock(url: url, title: title, isFavorite: true)
        let suggestion = Suggestion(bookmark: bookmark)

        guard case .bookmark = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(suggestion.url, url)
        XCTAssertEqual(suggestion.title, title)
    }

    func testWhenInitFromURL_ThenWebsiteSuggestionIsInitialized() {
        let url = URL(string: "https://www.duckduckgo.com")!
        let suggestion = Suggestion(url: url)

        guard case .website(let websiteUrl) = suggestion else {
            XCTFail("Wrong type of suggestion")
            return
        }

        XCTAssertEqual(suggestion.url, url)
        XCTAssertEqual(websiteUrl, url)
    }

}
