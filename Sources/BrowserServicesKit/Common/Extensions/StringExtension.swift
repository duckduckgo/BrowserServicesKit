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
    
    // Encodes plus symbols in a string so they are not treated as spaces on the web
    // Plus sign UTF-8 encoding is 0x2B
    func encodingPluses() -> String {
        replacingOccurrences(of: "+", with: "%2B")
    }
    
    // Replaces plus symbols in a string with the space character encoding
    // Space UTF-8 encoding is 0x20
    func encodingPlusesAsSpaces() -> String {
        return replacingOccurrences(of: "+", with: "%20")
    }

}
