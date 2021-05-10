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
        let suggestion = Suggestion(key: key, value: phraseValue, urlFactory: { _ in nil })

        XCTAssertEqual(suggestion, Suggestion.phrase(phrase: phraseValue))
    }

    func testWhenSuggestionKeyIsNotPhrase_ThenSuggestionIsUnknown() {
        let key = "Key"
        let value = "value"
        let suggestion = Suggestion(key: key, value: value)

        XCTAssertEqual(suggestion, Suggestion.unknown(value: value))
    }

    func testWhenSuggestionKeyIsURL_ThenSuggestionIsURL() {
        let key = Suggestion.phraseKey
        let phraseValue = "duckduckgo.com"
        let suggestion = Suggestion(key: key, value: phraseValue, urlFactory: URL.init(string:))

        XCTAssertEqual(suggestion, Suggestion.website(url: URL(string: phraseValue)!))
    }

}
