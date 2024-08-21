//
//  ErrorPageHTMLTemplate.swift
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
import ContentScopeScripts
import WebKit
import Common

public struct ErrorPageHTMLTemplate {

    public static var htmlFromTemplate: String {
        guard let file = ContentScopeScripts.Bundle.path(forResource: "index", ofType: "html", inDirectory: "pages/special-error") else {
            assertionFailure("HTML template not found")
            return ""
        }
        guard let html = try? String(contentsOfFile: file) else {
            assertionFailure("Should be able to load template")
            return ""
        }

        if let localizedFile = ContentScopeScripts.Bundle.path(forResource: "special-error", ofType: "json", inDirectory: "pages/special-error/locales/pl"), 
            let json = try? String(contentsOfFile: localizedFile) {
            return html.replacingOccurrences(of: "$LOCALE_STRINGS$", with: json.escapedUnicodeHtmlString(), options: .literal)
        }
        return html
    }

    

}

extension String {

    private static let unicodeHtmlCharactersMapping: [Character: String] = [
        "&": "&amp;",
        "\"": "&quot;",
        "'": "&apos;",
        "<": "&lt;",
        ">": "&gt;",
        "/": "&#x2F;",
        "!": "&excl;",
        "$": "&#36;",
        "%": "&percnt;",
        "=": "&#61;",
        "#": "&#35;",
        "@": "&#64;",
        "[": "&#91;",
        "\\": "&#92;",
        "]": "&#93;",
        "^": "&#94;",
        "`": "&#97;",
        "{": "&#123;",
        "}": "&#125;",
    ]
    func escapedUnicodeHtmlString() -> String {
        var result = ""

        for character in self {
            if let mapped = Self.unicodeHtmlCharactersMapping[character] {
                result.append(mapped)
            } else {
                result.append(character)
            }
        }

        return result
    }

}
