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
            query.count + 1)
        navigationalSuggestions = removeDuplicates(from: navigationalSuggestions,
                                                   maximum: maximumOfNavigationalSuggestions)

        // Split the Top Hits and the History and Bookmarks section
        let topHits = topHits(from: navigationalSuggestions)
        let historyAndBookmarkSuggestions = Array(navigationalSuggestions.dropFirst(topHits.count).filter { suggestion in
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
                                from suggestions: [Suggestion]) -> Suggestion? {
            guard suggestion.title == nil else {
                return nil
            }
            return suggestions.first(where: {
                $0.url?.naked == nakedUrl && $0.title != nil
            }) ?? nil
        }

        func bookmarkDuplicate(to suggestion: Suggestion,
                               nakedUrl: URL,
                               from sugestions: [Suggestion]) -> Suggestion? {
            guard case .historyEntry = suggestion else {
                return nil
            }
            return suggestions.first(where: {
                if case .bookmark = $0, $0.url?.naked == nakedUrl { return true }
                return false
            }) ?? nil
        }

        var newSuggestions = [Suggestion]()
        var urls = Set<URL>()

        for suggestion in suggestions {
            guard let suggestionUrl = suggestion.url,
                  let suggestionNakedUrl = suggestionUrl.naked,
                  !urls.contains(suggestionNakedUrl) else {
                continue
            }

            var newSuggestion: Suggestion?
            // The point of the code below is to prioritise duplicates that
            // provide a higher value

            // If there is a historyEntry and bookmark with the same URL, suggest the bookmark
            switch suggestion {
            case .historyEntry:
                newSuggestion = bookmarkDuplicate(to: suggestion, nakedUrl: suggestionNakedUrl, from: suggestions)
            case .bookmark, .phrase, .website, .unknown:
                break
            }

            // Sometimes, duplicates with a lower score have more information
            if newSuggestion == nil {
                switch suggestion {
                case .historyEntry:
                    newSuggestion = duplicateWithTitle(to: suggestion, nakedUrl: suggestionNakedUrl, from: suggestions)
                case .bookmark, .phrase, .website, .unknown:
                    break
                }
            }

            urls.insert(suggestionNakedUrl)
            newSuggestions.append(newSuggestion ?? suggestion)

            if let maximum = maximum, newSuggestions.count >= maximum {
                break
            }
        }

        return newSuggestions
    }

    // MARK: - Top Hits

    private func topHits(from suggestions: [Suggestion]) -> [Suggestion] {
        var topHits = [Suggestion]()

        for (i, suggestion) in suggestions.enumerated() {
            guard i <= Self.maximumNumberOfTopHits else { break }

            if suggestion.allowedInTopHits {
                topHits.append(suggestion)
            } else {
                break
            }
        }

        return topHits
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
