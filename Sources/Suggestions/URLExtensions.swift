//
//  URLExtensions.swift
//  DuckDuckGo
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

public extension URL {
    
    /// Creates a URL from a suggestion phrase.
    /// - Parameter phrase: The suggestion phrase to create the URL from.
    /// - Returns: A URL object if the suggestion phrase can be converted to a valid URL with a supported navigational scheme; otherwise, nil.
    static func makeURL(fromSuggestionPhrase phrase: String) -> URL? {
        guard let url = URL(trimmedAddressBarString: phrase),
              let scheme = url.scheme.map(NavigationalScheme.init),
              NavigationalScheme.hypertextSchemes.contains(scheme),
              url.isValid else {
            return nil
        }

        return url
    }
    
}
