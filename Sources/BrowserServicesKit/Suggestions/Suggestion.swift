//
//  Suggestion.swift
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

public enum Suggestion: Equatable {
    
    case phrase(phrase: String)
    case website(url: URL)
    case bookmark(title: String, url: URL, isFavorite: Bool)
    case historyEntry(title: String?, url: URL, allowedInTopHits: Bool)
    case unknown(value: String)

    var url: URL? {
        get {
            switch self {
            case .website(url: let url),
                 .historyEntry(title: _, url: let url, allowedInTopHits: _),
                 .bookmark(title: _, url: let url, isFavorite: _):
                return url
            case .phrase, .unknown:
                return nil
            }
        }
    }

    var title: String? {
        get {
            switch self {
            case .historyEntry(title: let title, url: _, allowedInTopHits: _):
                return title
            case .bookmark(title: let title, url: _, isFavorite: _):
                return title
            case .phrase, .website,.unknown:
                return nil
            }
        }
    }

    public var allowedForAutocompletion: Bool {
        switch self {
        case .historyEntry, .bookmark:
            return true
        case .phrase, .website,.unknown:
            return false
        }
    }

}

extension Suggestion {

    init(bookmark: Bookmark) {
        self = .bookmark(title: bookmark.title, url: bookmark.url, isFavorite: bookmark.isFavorite)
    }

    init(historyEntry: HistoryEntry) {
        let allowedInTopHits = !(historyEntry.failedToLoad || historyEntry.isDownload)
        self = .historyEntry(title: historyEntry.title, url: historyEntry.url, allowedInTopHits: allowedInTopHits)
    }

    init(url: URL) {
        self = .website(url: url)
    }

    static let phraseKey = "phrase"

    init(key: String, value: String) {
        if key == Self.phraseKey {
            self = .phrase(phrase: value.droppingWwwPrefix())
        } else {
            self = .unknown(value: value)
        }
    }

}
