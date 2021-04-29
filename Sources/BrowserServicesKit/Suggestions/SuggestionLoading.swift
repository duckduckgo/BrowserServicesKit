//
//  SuggestionLoading.swift
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

public protocol SuggestionLoading: AnyObject {

    func getSuggestions(query: Query,
                        maximum: Int,
                        completion: @escaping ([Suggestion]?, Error?) -> Void)

    var dataSource: SuggestionLoadingDataSource? { get set }

}

public class SuggestionLoader: SuggestionLoading {

    public static let defaultMaxOfSuggestions = 9
    static let remoteSuggestionsUrl = URL(string: "https://duckduckgo.com/ac/")!
    static let searchParameter = "q"

    public enum SuggestionLoaderError: Error {
        case noDataSource
        case failedToObtainData
    }

    public weak var dataSource: SuggestionLoadingDataSource?
    private var urlFactory: ((String) -> URL?)?

    public init(dataSource: SuggestionLoadingDataSource? = nil, urlFactory: ((String) -> URL?)? = nil) {
        self.dataSource = dataSource
        self.urlFactory = urlFactory
    }

    public func getSuggestions(query: Query,
                               maximum: Int,
                               completion: @escaping ([Suggestion]?, Error?) -> Void) {
        guard let dataSource = dataSource else {
            completion(nil, SuggestionLoaderError.noDataSource)
            return
        }

        if query.isEmpty {
            completion([], nil)
            return
        }

        let bookmarks = dataSource.bookmarks(for: self)
        var bookmarkSuggestions: [Suggestion]!
        var remoteSuggestions: [Suggestion]?
        var remoteSuggestionsError: Error?
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            // Bookmark suggestions
            bookmarkSuggestions = self.bookmarkSuggestions(from: bookmarks, for: query)
            group.leave()
        }

        // Remote suggestions
        group.enter()
        dataSource.suggestionLoading(self,
                                     suggestionDataFromUrl: Self.remoteSuggestionsUrl,
                                     withParameters: [Self.searchParameter: query]) { [weak self] data, error in
            defer { group.leave() }
            guard let self = self, let data = data else {
                remoteSuggestionsError = error
                return
            }

            do {
                remoteSuggestions = try self.remoteSuggestions(from: data)
            } catch {
                remoteSuggestionsError = error
            }
        }

        group.notify(queue: .global()) {
            let result = Self.result(maximum: maximum,
                                     bookmarkSuggestions: bookmarkSuggestions,
                                     remoteSuggestions: remoteSuggestions ?? [])

            DispatchQueue.main.async {
                guard !result.isEmpty || remoteSuggestionsError == nil else {
                    completion(nil, SuggestionLoaderError.failedToObtainData)
                    return
                }
                completion(result, nil)
            }
        }
    }

    // MARK: - Bookmark Suggestions

    static var minimumQueryLengthForBookmarkSuggestions = 2

    private func bookmarkSuggestions(from bookmarks: [Bookmark], for query: Query) -> [Suggestion] {
        guard query.count >= Self.minimumQueryLengthForBookmarkSuggestions else { return [] }

        let queryTokens = Score.tokens(from: query)

        return bookmarks
            // Score bookmarks
            .map { bookmark -> (bookmark: Bookmark, score: Score) in
                let score = Score(bookmark: bookmark, query: query, queryTokens: queryTokens)
                return (bookmark, score)
            }
            // Filter not relevant
            .filter { $0.score > 0 }
            // Sort according to the score
            .sorted { $0.score < $1.score }
            // Pick first two
            .prefix(2)
            // Create suggestion array
            .map { Suggestion(bookmark: $0.bookmark) }
    }

    // MARK: - Remote Suggestions

    private func remoteSuggestions(from data: Data) throws -> [Suggestion] {
        let decoder = JSONDecoder()
        let apiResult = try decoder.decode(APIResult.self, from: data)

        return apiResult.items
            .joined()
            .map { Suggestion(key: $0.key, value: $0.value, urlFactory: urlFactory) }
    }

    // MARK: - Merging

    private static func result(maximum: Int,
                               bookmarkSuggestions: [Suggestion],
                               remoteSuggestions: [Suggestion]) -> [Suggestion] {
        return Array((bookmarkSuggestions + remoteSuggestions).prefix(maximum))
    }

}

public protocol SuggestionLoadingDataSource: AnyObject {

    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Bookmark]

    func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                           suggestionDataFromUrl url: URL,
                           withParameters parameters: [String: String],
                           completion: @escaping (Data?, Error?) -> Void)

}
