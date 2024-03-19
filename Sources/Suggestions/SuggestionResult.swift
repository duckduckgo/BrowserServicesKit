//
//  SuggestionResult.swift
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

public struct SuggestionResult: Equatable {

    static var empty: SuggestionResult {
        SuggestionResult(topHits: [], duckduckgoSuggestions: [], historyAndBookmarks: [])
    }

    private(set) public var topHits: [Suggestion]
    private(set) public var duckduckgoSuggestions: [Suggestion]
    private(set) public var historyAndBookmarks: [Suggestion]

    public init(topHits: [Suggestion],
                duckduckgoSuggestions: [Suggestion],
                historyAndBookmarks: [Suggestion]) {
        self.topHits = topHits
        self.duckduckgoSuggestions = duckduckgoSuggestions
        self.historyAndBookmarks = historyAndBookmarks
    }

    public var isEmpty: Bool {
        topHits.isEmpty && duckduckgoSuggestions.isEmpty && historyAndBookmarks.isEmpty
    }

    public var all: [Suggestion] {
        topHits + duckduckgoSuggestions + historyAndBookmarks
    }

    public var count: Int {
        topHits.count + duckduckgoSuggestions.count + historyAndBookmarks.count
    }

    public var canBeAutocompleted: Bool {
        !topHits.isEmpty
    }

}
