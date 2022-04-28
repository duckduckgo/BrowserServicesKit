//
//  StringExtension.swift
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
import Punycode

extension String {

    public func trimWhitespace() -> String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func dropping(prefix: String) -> String {
        return hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    func droppingWwwPrefix() -> String {
        self.dropping(prefix: "www.")
    }

    // Replaces plus symbols in a string with the space character encoding
    // Space UTF-8 encoding is 0x20
    func encodingPlusesAsSpaces() -> String {
        return replacingOccurrences(of: "+", with: "%20")
    }
    
    func removingCharacters(in set: CharacterSet) -> String {
      let filtered = unicodeScalars.filter { !set.contains($0) }
      return String(String.UnicodeScalarView(filtered))
    }
    
    func autofillNormalized() -> String {
        let autofillCharacterSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        
        var normalizedString = self

        normalizedString = normalizedString.removingCharacters(in: autofillCharacterSet)
        normalizedString = normalizedString.folding(options: .diacriticInsensitive, locale: .current)
        normalizedString = normalizedString.localizedLowercase
        
        return normalizedString
    }

}

// MARK: - Punycode
extension String {
    public var punycodeEncodedHostname: String {
        return self.split(separator: ".")
            .map { String($0) }
            .map { $0.idnaEncoded ?? $0 }
            .joined(separator: ".")
    }
}
