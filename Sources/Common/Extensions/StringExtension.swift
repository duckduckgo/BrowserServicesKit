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

public typealias RegEx = NSRegularExpression

public func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    return (try? NSRegularExpression(pattern: pattern, options: options))!
}

extension RegEx {
    // from https://stackoverflow.com/a/25717506/73479
    static let hostName = regex("^(((?!-)[A-Za-z0-9-]{1,63}(?<!-)\\.)*[A-Za-z0-9-]{2,63})$", .caseInsensitive)
    // from https://stackoverflow.com/a/30023010/73479
    static let ipAddress = regex("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$",
                                 .caseInsensitive)
}

public extension String {

    static let localhost = "localhost"

    func length() -> Int {
        self.utf16.count
    }

    var fullRange: NSRange {
        return NSRange(location: 0, length: length())
    }

    func trimmingWhitespace() -> String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func dropping(prefix: String) -> String {
        return hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    func dropping(suffix: String) -> String {
        return hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }

    func droppingWwwPrefix() -> String {
        self.dropping(prefix: "www.")
    }

    var hashedSuffix: String? {
        if let idx = self.firstIndex(of: "#") {
            return String(self[idx...])
        }
        return nil
    }

    func droppingHashedSuffix() -> String {
        if let idx = self.firstIndex(of: "#") {
            return String(self[..<idx])
        }
        return self
    }
    
    func autofillNormalized() -> String {
        let autofillCharacterSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        
        var normalizedString = self

        normalizedString = normalizedString.removingCharacters(in: autofillCharacterSet)
        normalizedString = normalizedString.folding(options: .diacriticInsensitive, locale: .current)
        normalizedString = normalizedString.localizedLowercase
        
        return normalizedString
    }

    var isValidHost: Bool {
        return isValidHostname || isValidIpHost
    }

    var isValidHostname: Bool {
        return matches(.hostName)
    }

    var isValidIpHost: Bool {
        return matches(.ipAddress)
    }

    func matches(_ regex: NSRegularExpression) -> Bool {
        let matches = regex.matches(in: self, options: .anchored, range: self.fullRange)
        return matches.count == 1
    }

    func matches(pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return false
        }
        return matches(regex)
    }

    func replacing(_ regex: NSRegularExpression, with replacement: String) -> String {
        regex.stringByReplacingMatches(in: self, range: NSRange(location: 0, length: utf16.count), withTemplate: replacement)
    }

    func replacing(regex pattern: String, with replacement: String) -> String {
        self.replacing(regex(pattern), with: replacement)
    }

}

public extension StringProtocol {

    // Replaces plus symbols in a string with the space character encoding
    // Space UTF-8 encoding is 0x20
    func encodingPlusesAsSpaces() -> String {
        return replacingOccurrences(of: "+", with: "%20")
    }

    func percentEncoded(withAllowedCharacters allowedCharacters: CharacterSet) -> String {
        if let percentEncoded = self.addingPercentEncoding(withAllowedCharacters: allowedCharacters) {
            return percentEncoded
        }
        assertionFailure("Unexpected failure")
        return components(separatedBy: allowedCharacters.inverted).joined()
    }

    func removingCharacters(in set: CharacterSet) -> String {
        let filtered = unicodeScalars.filter { !set.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }

    // MARK: Punycode
    var punycodeEncodedHostname: String {
        return self.split(separator: ".")
            .map { String($0) }
            .map { $0.idnaEncoded ?? $0 }
            .joined(separator: ".")
    }

}
