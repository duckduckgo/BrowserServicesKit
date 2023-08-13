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

}

extension HistoryEntryMock {

    static var aHistory: [HistoryEntry] {
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
        [ BookmarkMock(url: "http://duckduckgo.com", title: "DuckDuckGo", isFavorite: true),
          BookmarkMock(url: "spreadprivacy.com", title: "Test 2", isFavorite: true),
          BookmarkMock(url: "wikipedia.org", title: "Wikipedia", isFavorite: false) ]
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
