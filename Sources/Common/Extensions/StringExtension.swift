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
import Network

public typealias RegEx = NSRegularExpression

public func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    return (try? NSRegularExpression(pattern: pattern, options: options))!
}

extension RegEx {
    // from https://stackoverflow.com/a/25717506/73479
    static let hostName = regex("^(((?!-)[A-Za-z0-9-]{1,63}(?<!-)\\.)*[A-Za-z0-9-]{2,63})$", .caseInsensitive)
}

public extension String {

    static let localhost = "localhost"

    var utf8data: Data {
        data(using: .utf8)!
    }

    /// Runs `body` over the UTF8-encoded content of the string in contiguous memory without performing byte copy if possible.
    /// If this string is not contiguous, this will first convert it to contiguous data using `.data(using: .utf8)` call.
    /// Note that it is unsafe to escape the pointer provided to `body`.
    func withUTF8data<R>(_ body: (Data) throws -> R) rethrows -> R {
        return try self.utf8.withContiguousStorageIfAvailable { buffer in
            let ptr = UnsafeMutableRawPointer(mutating: buffer.baseAddress!)
            let data = Data.init(bytesNoCopy: ptr, count: buffer.count, deallocator: .none)
            return try body(data)
        } ?? body(self.utf8data)
    }

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

    var hashedSuffixRange: PartialRangeFrom<String.Index>? {
        if let idx = self.firstIndex(of: "#") {
            return idx...
        } else if self.hasPrefix("about:"),
                  let range = self.range(of: "%23") {
            return range.lowerBound...
        }
        return nil
    }

    var hashedSuffix: String? {
        hashedSuffixRange.map { range in String(self[range]) }
    }

    func droppingHashedSuffix() -> String {
        if let range = self.hashedSuffixRange {
            guard range.lowerBound > self.startIndex else { return "" }
            return String(self[..<range.lowerBound])
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
        if IPv4Address(self) != nil || IPv6Address(self) != nil {
            return true
        }
        return false
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
