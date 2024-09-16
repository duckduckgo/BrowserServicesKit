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

    func testWhenTabsAndBookmarksAvailableOnMobile_ThenReplaceHistoryWithBoth() {

        let tabs = [
            BrowserTabMock(url: "http://duckduckgo.com", title: "DuckDuckGo"),
            BrowserTabMock(url: "http://ducktails.com", title: "Duck Tails"),
            BrowserTabMock(url: "wikipedia.org", title: "Wikipedia")
        ]

        let bookmarks = [
            BookmarkMock(url: "http://ducktails.com", title: "Duck Tails", isFavorite: false)
        ]

        let processing = SuggestionProcessing(platform: .mobile, urlFactory: Self.simpleUrlFactory)
        let result = processing.result(for: "Duck Tails",
                                       from: HistoryEntryMock.duckHistoryWithoutDuckDuckGo,
                                       bookmarks: bookmarks,
                                       internalPages: [],
                                       openTabs: tabs,
                                       apiResult: APIResult.anAPIResult)

        XCTAssertEqual(true, result?.topHits.contains(where: {
            if case .bookmark = $0, $0.title == "Duck Tails" {
                return true
            }
            return false
        }))
        XCTAssertEqual(true, result?.topHits.contains(where: {
            if case .openTab = $0, $0.title == "Duck Tails" {
                return true
            }
            return false
        }))
    }

    func testWhenTabsAvailableOnMobile_ThenReplaceHistoryLikeBookmarks() {

        let tabs = [
            BrowserTabMock(url: "http://duckduckgo.com", title: "DuckDuckGo"),
            BrowserTabMock(url: "http://ducktails.com", title: "Duck Tails"),
            BrowserTabMock(url: "wikipedia.org", title: "Wikipedia")
        ]

        let processing = SuggestionProcessing(platform: .desktop, urlFactory: Self.simpleUrlFactory)
        let result = processing.result(for: "Duck Tails",
                                       from: HistoryEntryMock.duckHistoryWithoutDuckDuckGo,
                                       bookmarks: [],
                                       internalPages: [],
                                       openTabs: tabs,
                                       apiResult: APIResult.anAPIResult)

        XCTAssertEqual(true, result?.topHits.contains(where: {
            if case .openTab = $0, $0.title == "Duck Tails" {
                return true
            }
            return false
        }))
    }

    func testWhenOnDesktop_ThenBookmarksNotInTopHitsWithoutHistoryVisits() {

        let processing = SuggestionProcessing(platform: .desktop, urlFactory: Self.simpleUrlFactory)
        let result = processing.result(for: "Duck",
                                       from: HistoryEntryMock.duckHistoryWithoutDuckDuckGo,
                                       bookmarks: BookmarkMock.someBookmarks,
                                       internalPages: [],
                                       openTabs: [],
                                       apiResult: APIResult.anAPIResult)

        XCTAssertEqual(false, result?.topHits.contains(where: { $0.title == "DuckDuckGo" }))
        XCTAssertEqual(1, result?.localSuggestions.count)
        XCTAssertEqual(true, result?.localSuggestions.contains(where: { $0.title == "DuckDuckGo" }))

    }

    func testWhenOnMobile_ThenBookmarksAlwaysInTopHits() {

        let processing = SuggestionProcessing(platform: .mobile, urlFactory: Self.simpleUrlFactory)
        let result = processing.result(for: "Duck",
                                              from: [],
                                              bookmarks: BookmarkMock.someBookmarks,
                                              internalPages: [],
                                              openTabs: [],
                                              apiResult: APIResult.anAPIResult)

        XCTAssertEqual(true, result?.topHits.contains(where: { $0.title == "DuckDuckGo" }))

    }

    func testWhenDuplicatesAreInSourceArrays_ThenTheOneWithTheBiggestInformationValueIsUsed() {
        func runAssertion(_ platform: Platform) {
            let processing = SuggestionProcessing(platform: platform, urlFactory: Self.simpleUrlFactory)
            let result = processing.result(for: "DuckDuckGo",
                                                  from: HistoryEntryMock.aHistory,
                                                  bookmarks: BookmarkMock.someBookmarks,
                                                  internalPages: InternalPage.someInternalPages,
                                                  openTabs: [],
                                                  apiResult: APIResult.anAPIResult)

            XCTAssertEqual(result!.topHits.count, 1)
            XCTAssertEqual(result!.topHits.first!.title, "DuckDuckGo")
        }

        // Same for both platforms
        runAssertion(.desktop)
        runAssertion(.mobile)
    }

    func testWhenBuildingTopHits_ThenOnlyWebsiteSuggestionsAreUsedForNavigationalSuggestions() {

        func runAssertion(_ platform: Platform) {
            let processing = SuggestionProcessing(platform: platform, urlFactory: Self.simpleUrlFactory)

            let result = processing.result(for: "DuckDuckGo",
                                                 from: HistoryEntryMock.aHistory,
                                                 bookmarks: BookmarkMock.someBookmarks,
                                                 internalPages: InternalPage.someInternalPages,
                                                 openTabs: [],
                                                 apiResult: APIResult.anAPIResultWithNav)

            XCTAssertEqual(result!.topHits.count, 2)
            XCTAssertEqual(result!.topHits.first!.title, "DuckDuckGo")
            XCTAssertEqual(result!.topHits.last!.url?.absoluteString, "http://www.example.com")
        }

        // Same for both platforms
        runAssertion(.desktop)
        runAssertion(.mobile)
    }

    func testWhenWebsiteInTopHits_ThenWebsiteRemovedFromSuggestions() {

        func runAssertion(_ platform: Platform) {
            let processing = SuggestionProcessing(platform: platform, urlFactory: Self.simpleUrlFactory)

            guard let result = processing.result(for: "DuckDuckGo",
                                                 from: [],
                                                 bookmarks: [],
                                                 internalPages: [],
                                                 openTabs: [],
                                                 apiResult: APIResult.anAPIResultWithNav) else {
                XCTFail("Expected result")
                return
            }

            XCTAssertEqual(result.topHits.count, 1)
            XCTAssertEqual(result.topHits[0].url?.absoluteString, "http://www.example.com")

            XCTAssertFalse(
                result.duckduckgoSuggestions.contains(where: {
                    if case .website(let url) = $0, url.absoluteString.hasSuffix("://www.example.com") {
                        return true
                    }
                    return false
                })
            )
        }
        // Same for both platforms
        runAssertion(.desktop)
        runAssertion(.mobile)
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

    static var duckHistoryWithoutDuckDuckGo: [HistorySuggestion] {
        [
            HistoryEntryMock(identifier: UUID(),
                           url: URL(string: "http://www.ducktails.com")!,
                           title: nil,
                           numberOfVisits: 100,
                           lastVisit: Date(),
                           failedToLoad: false,
                           isDownload: false),

            HistoryEntryMock(identifier: UUID(),
                           url: URL(string: "http://www.duck.com")!,
                           title: "DuckMail",
                           numberOfVisits: 300,
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

extension InternalPage {
    static var someInternalPages: [InternalPage] {
        [
            InternalPage(title: "Settings", url: URL(string: "duck://settings")!),
            InternalPage(title: "Bookmarks", url: URL(string: "duck://bookmarks")!),
            InternalPage(title: "Duck Player Settings", url: URL(string: "duck://bookmarks/duck-player")!),
        ]
    }
}
extension APIResult {

    static var anAPIResult: APIResult {
        var result = APIResult()
        result.items = [
            .init(phrase: "Test", isNav: nil),
            .init(phrase: "Test 2", isNav: nil),
            .init(phrase: "www.example.com", isNav: nil),
        ]
        return result
    }

    static var anAPIResultWithNav: APIResult {
        var result = APIResult()
        result.items = [
            .init(phrase: "Test", isNav: nil),
            .init(phrase: "Test 2", isNav: nil),
            .init(phrase: "www.example.com", isNav: true),
            .init(phrase: "www.othersite.com", isNav: false),
        ]
        return result
    }

}
