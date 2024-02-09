//
//  URLMacroTests.swift
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

import MacrosImplementation
import MacroTesting
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class URLMacroTests: XCTestCase {

    private let macros: [String: Macro.Type] = ["URL": URLMacro.self]

    func testWhenURLMacroAppliedToValidURLs_UrlIniIsGenerated() {
        let startLine = #line + 2
        let urls = [
            "http://example.com",
            "https://example.com",
            "http://localhost",
            "http://localdomain",
            "https://dax%40duck.com:123%3A456A@www.duckduckgo.com/te-st.php?test=S&info=test#fragment",
            "user:@something.local:9100",
            "user:passwOrd@localhost:5000",
            "user:%20@localhost:5000",
            "https://user:@something.local:9100",
            "https://user:passwOrd@localhost:5000",
            "https://user:%20@localhost:5000",
            "mailto:test@example.com",
            "http://192.168.1.1",
            "http://sheep%2B:P%40%24swrd@192.168.1.1",
            "data:text/vnd-example+xyz;foo=bar;base64,R0lGODdh",
            "http://192.168.0.1",
            "http://203.0.113.0",
            "http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]",
            "http://[2001:0db8::1]",
            "http://[::]:8080",
            "about:blank",
            "duck://newtab",
            "duck://welcome",
            "duck://settings",
            "duck://bookmarks",
            "duck://dbp",
            "about:newtab",
            "duck://home",
            "about:welcome",
            "about:home",
            "about:settings",
            "about:preferences",
            "duck://preferences",
            "about:config",
            "duck://config",
            "about:bookmarks",
            "about:user:pass@blank",
            "data:user:pass@text/vnd-example+xyz;foo=bar;base64,R0lGODdh",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
        ]

        for (idx, url) in urls.enumerated() {
            assertMacroExpansion(
                """
                #URL("\(url)")
                """,
                expandedSource:
                """
                URL(string: "\(url)")!
                """,
                macros: macros,
                line: UInt(startLine + idx)
            )
        }
    }

    func testWhenURLMacroAppliedToURLWithoutScheme_diagnosticsErrorIsReturned() {
        let startLine = #line + 2
        let urls = [
            "user@somehost.local:9091/index.html",
            "192.168.1.1",
            "duckduckgo.com",
            "example.com",
            "localhost",
            "localdomain",
            "user%40local:pa%24%24s@localhost:5000",
            "user%40local:pa%24%24s@localhost:5000",
            "sheep%2B:P%40%24swrd@192.168.1.1",
            "sheep%2B:P%40%24swrd@192.168.1.1/",
            "sheep%2B:P%40%24swrd@192.168.1.1:8900/",
            "sheep%2B:P%40%24swrd@xn--ls8h.la/?arg=b#1",
        ]

        for (idx, url) in urls.enumerated() {
            assertMacroExpansion(
                """
                #URL("\(url)")
                """,
                expandedSource:
                """
                #URL("\(url)")
                """,
                diagnostics: [
                    DiagnosticSpec(message: "URL must contain a scheme", line: 1, column: 1)
                ],
                macros: macros,
                line: UInt(startLine + idx)
            )
        }
    }

    func testWhenURLMacroAppliedToURLsWithInvalidCharacter_diagnosticsErrorIsReturned() {
        let startLine = #line + 2
        let urls: [(String, invalidCharacter: Character)] = [
            ("sheep%2B:P%40%24swrd@💩.la?arg=b#1", "💩"),
            ("https://www.duckduckgo .com/html?q=search", " "),
            ("мвд.рф", "м"),
            ("https://мвд.рф", "м"),
            ("https://sheep%2B:P%40%24swrd@💩.la", "💩"),
            ("https://www.duckduckgo.com/html?q =search", " "),
        ]

        for (idx, (url, char)) in urls.enumerated() {
            assertMacroExpansion(
                """
                #URL("\(url)")
                """,
                expandedSource:
                """
                #URL("\(url)")
                """,
                diagnostics: [
                    DiagnosticSpec(message: """
                    "\(url)" has invalid character at index \(url.distance(from: url.startIndex, to: url.firstIndex(of: char)!)) (\(char))
                    """, line: 1, column: 1)
                ],
                macros: macros,
                line: UInt(startLine + idx)
            )
        }
    }

    func testWhenInvalidArgumentProvided_URLMacroFails() {
        assertMacro(macros, record: false) {
            """
            let s = "duckduckgo.com/"
            let _=#URL(s)
            """
        } diagnostics: {
            """
            let s = "duckduckgo.com/"
            let _=#URL(s)
                  ┬──────
                  ╰─ 🛑 #URL argument should be a String literal
            """
        }

        assertMacro(macros, record: false) {
            """
            #URL(duckduckgo)
            """
        } diagnostics: {
            """
            #URL(duckduckgo)
            ┬───────────────
            ╰─ 🛑 #URL argument should be a String literal
            """
        }

        assertMacro(macros, record: false) {
            """
            #URL(1)
            """
        } diagnostics: {
            """
            #URL(1)
            ┬──────
            ╰─ 🛑 #URL argument should be a String literal
            """
        }
    }

    func testWhenTooManyArgsProvided_URLMacroFails() {
        assertMacro(macros, record: false) {
            """
            #URL("duckduckgo.com", "duckduckgo.com")
            """
        } diagnostics: {
            """
            #URL("duckduckgo.com", "duckduckgo.com")
            ┬───────────────────────────────────────
            ╰─ 🛑 #URL macro should have one String literal argument
            """
        }
    }

}
