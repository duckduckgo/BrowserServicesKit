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
import Common

/// Class encapsulates the whole ordering and filtering algorithm
/// It takes query, history, bookmarks, and apiResult as input parameters
/// The output is instance of SuggestionResult
final class SuggestionProcessing {

    private var urlFactory: (String) -> URL?

    init(urlFactory: @escaping (String) -> URL?) {
        self.urlFactory = urlFactory
    }

    func result(for query: Query,
                from history: [HistorySuggestion],
                bookmarks: [Bookmark],
                internalPages: [InternalPage],
                apiResult: APIResult?) -> SuggestionResult? {
        let query = query.lowercased()

        let duckDuckGoSuggestions = (try? self.duckDuckGoSuggestions(from: apiResult)) ?? []

        // Get domain suggestions from the DuckDuckGo Suggestions section (for the Top Hits section)
        let duckDuckGoDomainSuggestions = duckDuckGoSuggestions.compactMap { suggestion -> Suggestion? in
            // The JSON response tells us explicitly what is navigational now, so we only need to find website suggestions here
            if case .website = suggestion {
                return suggestion
            }
            return nil
        }

        // Get best matches from history and bookmarks
        let allLocalSuggestions = localSuggestions(from: history, bookmarks: bookmarks, internalPages: internalPages, query: query)

        // Combine HaB and domains into navigational suggestions and remove duplicates
        let navigationalSuggestions = allLocalSuggestions + duckDuckGoDomainSuggestions

        let maximumOfNavigationalSuggestions = min(
            Self.maximumNumberOfSuggestions - Self.minimumNumberInSuggestionGroup,
            query.count + 1)
        let mergedSuggestions = merge(navigationalSuggestions, maximum: maximumOfNavigationalSuggestions)

        // Split the Top Hits and the History and Bookmarks section
        let topHits = topHits(from: mergedSuggestions)
        let localSuggestions = Array(mergedSuggestions.dropFirst(topHits.count).filter { suggestion in
            switch suggestion {
            case .bookmark, .historyEntry, .internalPage:
                return true
            default:
                return false
            }
        })

        let dedupedDuckDuckGoSuggestions = removeDuplicateWebsiteSuggestions(in: topHits, from: duckDuckGoSuggestions)

        return makeResult(topHits: topHits,
                          duckduckgoSuggestions: dedupedDuckDuckGoSuggestions,
                          localSuggestions: localSuggestions)
    }

    private func removeDuplicateWebsiteSuggestions(in sourceSuggestions: [Suggestion], from targetSuggestions: [Suggestion]) -> [Suggestion] {
        return targetSuggestions.compactMap { targetSuggestion in
            if case .website = targetSuggestion, sourceSuggestions.contains(where: {
                targetSuggestion == $0
            }) {
                return nil
            }
            return targetSuggestion
        }
    }

    // MARK: - DuckDuckGo Suggestions

    private func duckDuckGoSuggestions(from result: APIResult?) throws -> [Suggestion]? {
        return result?.items
            .compactMap {
                guard let phrase = $0.phrase else {
                    return nil
                }
                return Suggestion(phrase: phrase, isNav: $0.isNav ?? false)
            }
    }

    // MARK: - History and Bookmarks

    private func localSuggestions(from history: [HistorySuggestion], bookmarks: [Bookmark], internalPages: [InternalPage], query: Query) -> [Suggestion] {
        enum LocalSuggestion {
            case bookmark(Bookmark)
            case history(HistorySuggestion)
            case internalPage(InternalPage)
        }
        let localSuggestions: [LocalSuggestion] = bookmarks.map(LocalSuggestion.bookmark) + history.map(LocalSuggestion.history) + internalPages.map(LocalSuggestion.internalPage)
        let queryTokens = Score.tokens(from: query)

        let result: [Suggestion] = localSuggestions
            // Score items
            .map { item -> (item: LocalSuggestion, score: Score) in
                let score = switch item {
                case .bookmark(let bookmark):
                    Score(bookmark: bookmark, query: query, queryTokens: queryTokens)
                case .history(let historyEntry):
                    Score(historyEntry: historyEntry, query: query, queryTokens: queryTokens)
                case .internalPage(let internalPage):
                    Score(internalPage: internalPage, query: query, queryTokens: queryTokens)
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
                case .bookmark(let bookmark):
                    return Suggestion(bookmark: bookmark)
                case .history(let historyEntry):
                    return Suggestion(historyEntry: historyEntry)
                case .internalPage(let internalPage):
                    return Suggestion(internalPage: internalPage)
                }
            }

        return result
    }

    // MARK: - Elimination of duplicates and merging of suggestions

    // The point of this method is to prioritise duplicates that
    // provide a higher value or replace history suggestions with bookmark suggestions
    private func merge(_ suggestions: [Suggestion], maximum: Int? = nil) -> [Suggestion] {

        // Finds a duplicate with the same URL and available title
        func findDuplicateContainingTitle(_ suggestion: Suggestion,
                                          nakedUrl: URL,
                                          from suggestions: [Suggestion]) -> Suggestion? {
            guard suggestion.title == nil else {
                return nil
            }
            return suggestions.first(where: {
                $0.url?.naked == nakedUrl && $0.title != nil
            }) ?? nil
        }

        // Finds a bookmark duplicate for history entry and copies allowedInTopHits value
        func findBookmarkDuplicate(to historySuggestion: Suggestion,
                                   nakedUrl: URL,
                                   from sugestions: [Suggestion]) -> Suggestion? {
            guard case .historyEntry = historySuggestion else {
                return nil
            }
            if let newSuggestion = suggestions.first(where: {
                if case .bookmark = $0, $0.url?.naked == nakedUrl { return true }
                return false
            }), case let Suggestion.bookmark(title: title, url: url, isFavorite: isFavorite, allowedInTopHits: _) = newSuggestion {
                #if os(macOS)
                // Copy allowedInTopHits from original suggestion
                return Suggestion.bookmark(title: title,
                                           url: url,
                                           isFavorite: isFavorite,
                                           allowedInTopHits: historySuggestion.allowedInTopHits)
                #else
                return Suggestion.bookmark(title: title,
                                           url: url,
                                           isFavorite: isFavorite,
                                           allowedInTopHits: true)
                #endif
            } else {
                return nil
            }
        }

        // Finds a history entry duplicate for bookmark
        func findAndMergeHistoryDuplicate(with bookmarkSuggestion: Suggestion,
                                          nakedUrl: URL,
                                          from sugestions: [Suggestion]) -> Suggestion? {
            guard case let .bookmark(title: title, url: url, isFavorite: isFavorite, allowedInTopHits: _) = bookmarkSuggestion else {
                return nil
            }
            if let historySuggestion = suggestions.first(where: {
                if case .historyEntry = $0, $0.url?.naked == nakedUrl { return true }
                return false
            }), historySuggestion.allowedInTopHits {
                #if os(macOS)
                return Suggestion.bookmark(title: title,
                                           url: url,
                                           isFavorite: isFavorite,
                                           allowedInTopHits: historySuggestion.allowedInTopHits)
                #else
                return Suggestion.bookmark(title: title,
                                           url: url,
                                           isFavorite: isFavorite,
                                           allowedInTopHits: true)
                #endif
            } else {
                return nil
            }
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

            switch suggestion {
            case .historyEntry:
                // If there is a historyEntry and bookmark with the same URL, suggest the bookmark
                newSuggestion = findBookmarkDuplicate(to: suggestion, nakedUrl: suggestionNakedUrl, from: suggestions)
            case .bookmark:
                newSuggestion = findAndMergeHistoryDuplicate(with: suggestion, nakedUrl: suggestionNakedUrl, from: suggestions)
            case .phrase, .website, .internalPage, .unknown:
                break
            }

            // Sometimes, duplicates with a lower score have more information
            if newSuggestion == nil {
                switch suggestion {
                case .historyEntry:
                    newSuggestion = findDuplicateContainingTitle(suggestion, nakedUrl: suggestionNakedUrl, from: suggestions)
                case .bookmark, .phrase, .website, .internalPage, .unknown:
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
                            localSuggestions: [Suggestion]) -> SuggestionResult {
        // Top Hits
        let topHits = Array(topHits.prefix(2))
        var total = topHits.count

        // History and Bookmarks
        let prefixForLocalSuggestions = Self.maximumNumberOfSuggestions - (total + Self.minimumNumberInSuggestionGroup)
        let localSuggestions = Array(localSuggestions.prefix(prefixForLocalSuggestions))
        total += localSuggestions.count

        // DuckDuckGo Suggestions
        let prefixForDuckDuckGoSuggestions = Self.maximumNumberOfSuggestions - total
        let duckduckgoSuggestions = Array(duckduckgoSuggestions.prefix(prefixForDuckDuckGoSuggestions))

        return SuggestionResult(topHits: topHits,
                                duckduckgoSuggestions: duckduckgoSuggestions,
                                localSuggestions: localSuggestions)
    }

}
