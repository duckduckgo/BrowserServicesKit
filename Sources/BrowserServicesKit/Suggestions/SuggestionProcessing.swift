//
//  SuggestionProcessing.swift
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

import Foundation

/// Class encapsulates the whole ordering and filtering algorithm
/// It takes query, history, bookmarks, and apiResult as input parameters
/// The output is instance of SuggestionResult
final class SuggestionProcessing {

    private var urlFactory: (String) -> URL?

    init(urlFactory: @escaping (String) -> URL?) {
        self.urlFactory = urlFactory
    }

    func result(for query: Query,
                from history: [HistoryEntry],
                bookmarks: [Bookmark],
                apiResult: APIResult?) -> SuggestionResult? {
        let query = query.lowercased()

        let duckDuckGoSuggestions = (try? self.duckDuckGoSuggestions(from: apiResult)) ?? []

        // Get domain suggestions from the DuckDuckGo Suggestions section (for the Top Hits section)
        let duckDuckGoDomainSuggestions = duckDuckGoSuggestions.compactMap { suggestion -> Suggestion? in
            guard case let .phrase(phrase) = suggestion, let url = urlFactory(phrase) else {
                return nil
            }

            return Suggestion(url: url)
        }

        // Get best matches from history and bookmarks
        let allHistoryAndBookmarkSuggestions = historyAndBookmarkSuggestions(from: history,
                                                                          bookmarks: bookmarks,
                                                                          query: query)

        // Combine HaB and domains into navigational suggestions and remove duplicates
        var navigationalSuggestions = allHistoryAndBookmarkSuggestions + duckDuckGoDomainSuggestions

        let maximumOfNavigationalSuggestions = min(
            Self.maximumNumberOfSuggestions - Self.minimumNumberInSuggestionGroup,
            query.count * 2)
        navigationalSuggestions = removeDuplicates(from: navigationalSuggestions,
                                                   maximum: maximumOfNavigationalSuggestions)

        // Split the Top Hits and the History and Bookmarks section
        let topHits = Array(navigationalSuggestions.prefix(2))
        let historyAndBookmarkSuggestions = Array(navigationalSuggestions.dropFirst(2).filter { suggestion in
            switch suggestion {
            case .bookmark, .historyEntry:
                return true
            default:
                return false
            }
        })

        return makeResult(topHits: topHits,
                          duckduckgoSuggestions: duckDuckGoSuggestions,
                          historyAndBookmarks: historyAndBookmarkSuggestions)
    }

    // MARK: - DuckDuckGo Suggestions

    private func duckDuckGoSuggestions(from result: APIResult?) throws -> [Suggestion]? {
        // TODO add query as duckduckgo suggestion
        return result?.items
            .joined()
            .map { Suggestion(key: $0.key, value: $0.value) }
    }

    // MARK: - History and Bookmarks

    private func historyAndBookmarkSuggestions(from history: [HistoryEntry], bookmarks: [Bookmark], query: Query) -> [Suggestion] {
        let historyAndBookmarks: [Any] = bookmarks + history
        let queryTokens = Score.tokens(from: query)

        let historyAndBookmarkSuggestions: [Suggestion] = historyAndBookmarks
            // Score items
            .map { item -> (item: Any, score: Score) in
                let score: Score
                switch item {
                case let bookmark as Bookmark:
                    score = Score(bookmark: bookmark, query: query, queryTokens: queryTokens)
                case let historyEntry as HistoryEntry:
                    score = Score(historyEntry: historyEntry, query: query, queryTokens: queryTokens)
                default:
                    score = 0
                }
                return (item, score)
            }
            // Filter not relevant
            .filter { $0.score > 0 }
            // Sort according to the score
            .sorted { $0.score > $1.score }
            // Create suggestion array
            .compactMap { 
                switch $0.item {
                case let bookmark as Bookmark:
                    return Suggestion(bookmark: bookmark)
                case let historyEntry as HistoryEntry:
                    return Suggestion(historyEntry: historyEntry)
                default:
                    return nil
                }
            }

        return historyAndBookmarkSuggestions
    }

    // MARK: - Elimination of duplicates

    private func removeDuplicates(from suggestions: [Suggestion], maximum: Int? = nil) -> [Suggestion] {

        func duplicateWithTitle(to suggestion: Suggestion,
                                nakedUrl: URL,
                                from suggestions: [Suggestion]) -> Suggestion {
            guard suggestion.title == nil else {
                return suggestion
            }
            return suggestions.first(where: {
                $0.url?.naked == nakedUrl && $0.title != nil
            }) ?? suggestion
        }

        var newSuggestions = [Suggestion]()
        var urls = Set<URL>()

        for suggestion in suggestions {
            guard let suggestionUrl = suggestion.url,
                  let suggestionNakedUrl = suggestionUrl.naked,
                  !urls.contains(suggestionNakedUrl) else {
                continue
            }

            // Sometimes, duplicates with a lower score have more information
            // The point of the code below is to prioritise duplicates that
            // provide a bigger value
            var suggestion = suggestion
            switch suggestion {
            case .bookmark, .historyEntry:
                suggestion = duplicateWithTitle(to: suggestion, nakedUrl: suggestionNakedUrl, from: suggestions)
            case .phrase, .website, .unknown:
                break
            }

            urls.insert(suggestionNakedUrl)
            newSuggestions.append(suggestion)

            if let maximum = maximum, newSuggestions.count >= maximum {
                break
            }
        }

        return newSuggestions
    }

    // MARK: - Cutting off and making the result

    static let maximumNumberOfSuggestions = 12
    static let maximumNumberOfTopHits = 2
    static let minimumNumberInSuggestionGroup = 5

    private func makeResult(topHits: [Suggestion],
                    duckduckgoSuggestions: [Suggestion],
                    historyAndBookmarks: [Suggestion]) -> SuggestionResult {
        // Top Hits
        let topHits = Array(topHits.prefix(2))
        var total = topHits.count

        // History and Bookmarks
        let prefixForHistoryAndBookmarks = Self.maximumNumberOfSuggestions - (total + Self.minimumNumberInSuggestionGroup)
        let historyAndBookmarks = Array(historyAndBookmarks.prefix(prefixForHistoryAndBookmarks))
        total += historyAndBookmarks.count

        // DuckDuckGo Suggestions
        let prefixForDuckDuckGoSuggestions = Self.maximumNumberOfSuggestions - total
        let duckduckgoSuggestions = Array(duckduckgoSuggestions.prefix(prefixForDuckDuckGoSuggestions))

        return SuggestionResult(topHits: topHits,
                                duckduckgoSuggestions: duckduckgoSuggestions,
                                historyAndBookmarks: historyAndBookmarks)
    }

}
