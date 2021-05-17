//
//  Score.swift
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

typealias Score = Int

extension Score {
    
    init(title: String?, url: URL, visitCount: Int, query: Query, queryTokens: [Query]? = nil) {
        // To optimize, query tokens can be precomputed
        let queryTokens = queryTokens ?? Self.tokens(from: query)

        var score = 0
        let lowercasedTitle = title?.lowercased() ?? ""

        // Exact matches - full query
        let queryCount = query.count
        if queryCount > 1 && lowercasedTitle.starts(with: query) { // High score for exact match from the begining of the title
            score += 20000
        } else if queryCount > 2 && lowercasedTitle.contains(" \(query)") { // Exact match from the begining of the word within string.
            score += 10000
        }

        let domain = url.host?.drop(prefix: "www.") ?? ""

        // Tokenized matches
        if queryTokens.count > 1 {
            var matchesAllTokens = true
            for token in queryTokens {
                // Match only from the begining of the word to avoid unintuitive matches.
                if !lowercasedTitle.starts(with: token) && !lowercasedTitle.contains(" \(token)") && !domain.starts(with: token) {
                    matchesAllTokens = false
                    break
                }
            }

            if matchesAllTokens {
                // Score tokenized matches
                score += 1000

                // Boost score if first token matches:
                if let firstToken = queryTokens.first { // domain - high score boost
                    if domain.starts(with: firstToken) {
                        score += 30000
                    } else if lowercasedTitle.starts(with: firstToken) { // begining of the title - moderate score boost
                        score += 5000
                    }
                }
            }
        } else {
            // High score for matching domain in the URL
            if let firstToken = queryTokens.first {
                if domain.starts(with: firstToken) {
                    score += 30000

                    // Prioritize root URLs most
                    if url.isRoot { score += 200000 }
                } else if firstToken.count > 2 && domain.contains(firstToken) {
                    score += 15000
                    if url.isRoot { score += 200000 }
                }
            }
        }

        // If there are matches, add visitCount to prioritise more visited
        if score > 0 { score += visitCount }

        self = score
    }

    init(bookmark: Bookmark, query: Query, queryTokens: [Query]? = nil) {
        self.init(title: bookmark.title, url: bookmark.url, visitCount: 0, query: query, queryTokens: queryTokens)
    }

    init(historyEntry: HistoryEntry, query: Query, queryTokens: [Query]? = nil) {
        self.init(title: historyEntry.title ?? "", url: historyEntry.url, visitCount: historyEntry.numberOfVisits, query: query, queryTokens: queryTokens)
    }

    static func tokens(from query: Query) -> [Query] {
        return query
            .split(whereSeparator: {
                $0.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
            })
            .filter { !$0.isEmpty }
            .map { String($0).lowercased() }
    }

}
