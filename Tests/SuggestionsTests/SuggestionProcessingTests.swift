//
//  SuggestionProcessingTests.swift
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

@testable import Suggestions

final class SuggestionProcessingTests: XCTestCase {

    static let simpleUrlFactory: (String) -> URL? = { _ in return nil }

    func testWhenDuplicatesAreInSourceArrays_ThenTheOneWithTheBiggestInformationValueIsUsed() {
        let processing = SuggestionProcessing(urlFactory: Self.simpleUrlFactory)
        let result = processing.result(for: "DuckDuckGo",
                                       from: HistoryEntryMock.aHistory,
                                       bookmarks: BookmarkMock.someBookmarks,
                                       apiResult: APIResult.anAPIResult)

        XCTAssertEqual(result!.topHits.count, 1)
        XCTAssertEqual(result!.topHits.first!.title, "DuckDuckGo")
    }

    func testWhenDuckDuckGoSuggestionContainsURLThenDoNotShowAsSearchTerm() throws {
        // GIVEN
        let processing = SuggestionProcessing(urlFactory: URL.makeURL(fromSuggestionPhrase:))
        let facebookURLSearchTermSuggestion = Suggestion(key: Suggestion.phraseKey, value: "www.acer.com/ac/en/US/content/home")

        // WHEN
        let result = processing.result(
            for: "ace",
            from: [],
            bookmarks: [],
            apiResult: .aceAPIResult
        )

        // THEN
        let duckduckGoSuggestions = try XCTUnwrap(result?.duckduckgoSuggestions)
        XCTAssertEqual(duckduckGoSuggestions.count, 4)
        XCTAssertFalse(duckduckGoSuggestions.contains(facebookURLSearchTermSuggestion))
    }

}

extension HistoryEntryMock {

    static var aHistory: [HistorySuggestion] {
        [ HistoryEntryMock(identifier: UUID(),
                           url: URL(string: "http://www.duckduckgo.com")!,
                           title: nil,
                           numberOfVisits: 1000,
                           lastVisit: Date(),
                           failedToLoad: false,
                           isDownload: false)
        ]
    }

}

extension BookmarkMock {

    static var someBookmarks: [Bookmark] {
        [
            BookmarkMock(url: "http://duckduckgo.com", title: "DuckDuckGo", isFavorite: true),
            BookmarkMock(url: "spreadprivacy.com", title: "Test 2", isFavorite: true),
            BookmarkMock(url: "wikipedia.org", title: "Wikipedia", isFavorite: false),
            BookmarkMock(url: "www.facebook.com", title: "Facebook", isFavorite: true),
        ]
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

    static let aceAPIResult: APIResult = {
        var result = APIResult()
        result.items = [
            [ "phrase": "acecqa" ],
            [ "phrase": "acer" ],
            [ "phrase": "www.acer.com/ac/en/US/content/home" ],
            [ "phrase": "ace hotel sydney" ],
            [ "phrase": "acer drivers" ],
        ]
        return result
    }()

}
