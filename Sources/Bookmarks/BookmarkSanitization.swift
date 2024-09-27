//
//  BookmarkSanitization.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

/// Provides strategies to sanitize edited Bookmark.
public enum BookmarkSanitization {

    /// Treats input as a potentially navigational address, appending scheme and fixing common known issues
    case navigational

    /// Provides a custom sanitization function
    case custom((BookmarkEntity) -> Void)

    func sanitize(_ bookmark: BookmarkEntity) {
        switch self {
        case .navigational:
            navigationalSanitization(bookmark)
        case .custom(let sanitize):
            sanitize(bookmark)
        }
    }

    private func navigationalSanitization(_ bookmark: BookmarkEntity) {
        guard let url = bookmark.url else {
            return
        }

        bookmark.url = URL(trimmedAddressBarString: url)?.absoluteString ?? url
    }
}
