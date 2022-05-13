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
@testable import BrowserServicesKit

final class SuggestionProcessingTests: XCTestCase {

    static let simpleUrlFactory: (String) -> URL? = { string in return nil }

    func testWhenDuplicatesAreInSourceArrays_ThenTheOneWithTheBiggestInformationValueIsUsed() {
        let processing = SuggestionProcessing(urlFactory: Self.simpleUrlFactory)
        let result = processing.result(for: "DuckDuckGo",
                                       from: HistoryEntryMock.aHistory,
                                       bookmarks: BookmarkMock.someBookmarks,
                                       apiResult: APIResult.anAPIResult)

        XCTAssertEqual(result!.topHits.count, 1)
        XCTAssertEqual(result!.topHits.first!.title, "DuckDuckGo")
    }

    func testWhenThereAreMoreSuggestionsThanAllowedMaximum_ThenAllDuckDuckGoSuggestionsAreUsed() {

        // create enough history entries that all suggestions have to be truncated
        let suggestionsCount = 9
        let historyEntriesCount = SuggestionProcessing.maximumNumberOfSuggestions - suggestionsCount + 5

        var apiResult = APIResult()
        (1...suggestionsCount).forEach {
            apiResult.items.append(["phrase": String($0)])
        }

        var history = [HistoryEntry]()
        (1...historyEntriesCount).forEach { i in
            history.append(HistoryEntryMock.mock("https://duckduckgo.com/\(i)"))
        }

        let processing = SuggestionProcessing(urlFactory: Self.simpleUrlFactory)
        let result = processing.result(for: "DuckDuckGo",
                                       from: history,
                                       bookmarks: [],
                                       apiResult: apiResult)

        XCTAssertEqual(result!.count, SuggestionProcessing.maximumNumberOfSuggestions)
        XCTAssertEqual(result!.duckduckgoSuggestions.count, apiResult.items.count)
    }

    func testWhenThereAreDuckDuckGoNavigationalSuggestions_ThenTheyAreDeduplicated() {

        let suggestionsCount = 9
        // create enough history entries that all suggestions have to be truncated
        let historyEntriesCount = SuggestionProcessing.maximumNumberOfSuggestions - suggestionsCount + 5

        var apiResult = APIResult()
        (1...suggestionsCount-1).forEach {
            apiResult.items.append(["phrase": String($0)])
        }
        apiResult.items.append(["phrase": "duckduckgo.com/1"])

        var history = [HistoryEntry]()
        (1...historyEntriesCount).forEach { i in
            history.append(HistoryEntryMock.mock("https://duckduckgo.com/\(i)"))
        }

        let processing = SuggestionProcessing(urlFactory: { phrase in
            if phrase == "duckduckgo.com/1" {
                return URL(string: "https://duckduckgo.com/1")
            }
            return nil
        })
        let result = processing.result(for: "DuckDuckGo",
                                       from: history,
                                       bookmarks: [],
                                       apiResult: apiResult)

        XCTAssertEqual(result!.count, SuggestionProcessing.maximumNumberOfSuggestions)
        XCTAssertEqual(result!.duckduckgoSuggestions.count, apiResult.items.count - 1)
        XCTAssertEqual(result!.historyAndBookmarks.count, SuggestionProcessing.maximumNumberOfSuggestions - result!.topHits.count - suggestionsCount + 1)
    }
}

extension HistoryEntryMock {

    static var aHistory: [HistoryEntry] {
        [
            HistoryEntryMock.mock("http://www.duckduckgo.com")
        ]
    }

    static func mock(_ urlString: String) -> HistoryEntry {
        HistoryEntryMock(
            identifier: UUID(),
            url: URL(string: urlString)!,
            title: nil,
            numberOfVisits: 1000,
            lastVisit: Date(),
            failedToLoad: false,
            isDownload: false
        )
    }

}

extension BookmarkMock {

    static var someBookmarks: [Bookmark] {
        [ BookmarkMock(url: URL(string: "http://duckduckgo.com")!, title: "DuckDuckGo", isFavorite: true),
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
