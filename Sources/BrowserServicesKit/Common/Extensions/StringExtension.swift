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

    // MARK: - Hostname validation

    public static let localhost = "localhost"
    static let localDomain = "local"

    /**
     * Performs hostname validation.
     *
     * If `validateDomain` is `true`, checks the sender against Public Suffix List
     * (and `.local` domain). This mode is useful when the user has not provided
     * URL scheme in the input and we only want to convert the input to a URL
     * if the domain is a known.
     *
     * When `validateDomain` is `false` it only tries to match the sender with
     * a hostname regular expression. This mode is useful to validate if
     * the URL provided by the user passes formal verification, i.e. does not
     * contain reserved characters.
     */
    public func isValidHost(validateDomain: Bool) -> Bool {
        if self == .localhost {
            return true
        }
        if validateDomain {
            if TLDValidator.shared.isHostnameWithValidTLD(self) || lastDomainComponent == .localDomain {
                return true
            }
        } else {
            if matches(.hostName) {
                return true
            }
        }

        return isValidIpHost
    }

    var isValidIpHost: Bool {
        return matches(.ipAddress)
    }

    var lastDomainComponent: String? {
        let components = components(separatedBy: ".")
        guard components.count > 1 else {
            return nil
        }
        return components.last
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

// MARK: - Regular Expressions

extension String {

    public func matches(_ regex: NSRegularExpression) -> Bool {
        let matches = regex.matches(in: self, options: .anchored, range: NSRange(location: 0, length: self.utf16.count))
        return matches.count == 1
    }
}

public func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    // swiftlint:disable:next force_try
    return try! NSRegularExpression(pattern: pattern, options: options)
}

public typealias RegEx = NSRegularExpression

private extension RegEx {
    // from https://stackoverflow.com/a/25717506/73479
    static let hostName = regex("^(((?!-)[A-Za-z0-9-]{1,63}(?<!-)\\.)*[A-Za-z0-9-]{2,63})$", .caseInsensitive)
    // from https://stackoverflow.com/a/30023010/73479
    static let ipAddress = regex("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$",
                                 .caseInsensitive)
}
