//
//  URLMacro.swift
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
import SwiftSyntax
import SwiftSyntaxMacros

/// Compile-time validated URL instantiation
/// - Returns: URL instance if provided string argument is a valid URL
/// - Throws: Compile-time error if provided string argument is not a valid URL
/// - Usage: `let url = #URL("https://duckduckgo.com")`
public struct URLMacro: ExpressionMacro {

    static let invalidCharacters = CharacterSet.urlQueryAllowed
        .union(CharacterSet(charactersIn: "%+?#[]"))
        .inverted
    static let urlSchemeAllowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))

    public static func expansion(of node: some SwiftSyntax.FreestandingMacroExpansionSyntax, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> SwiftSyntax.ExprSyntax {

        guard node.argumentList.count == 1 else {
            throw MacroError.message("#URL macro should have one String literal argument")
        }
        guard let literal = node.argumentList.first?.expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              let string = literal.segments.first?.as(StringSegmentSyntax.self)?.content else {
            throw MacroError.message("#URL argument should be a String literal")
        }

        if let idx = string.text.rangeOfCharacter(from: Self.invalidCharacters)?.lowerBound {
            throw MacroError.message("\"\(string.text)\" has invalid character at index \(string.text.distance(from: string.text.startIndex, to: idx)) (\(string.text[idx]))")
        }
        guard let scheme = string.text.range(of: ":").map({ string.text[..<$0.lowerBound] }),
              scheme.rangeOfCharacter(from: Self.urlSchemeAllowedCharacters.inverted) == nil else {
            throw MacroError.message("URL must contain a scheme")
        }
        guard let url = URL(string: string.text) else {
            throw MacroError.message("\"\(string.text)\" is not a valid URL")
        }
        guard url.scheme == String(scheme) else {
            throw MacroError.message("URL must contain a scheme")
        }
        guard url.absoluteString == string.text else {
            throw MacroError.message("Resulting URL \"\(url.absoluteString)\" is not equal to \"\(string.text)\"")
        }

        return "URL(string: \"\(raw: string.text)\")!"
    }

}
