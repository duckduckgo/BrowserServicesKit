//
//  ScoreTests.swift
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

import XCTest
@testable import BrowserServicesKit

final class ScoreTests: XCTestCase {

    func testWhenQueryIsJustWhitespaces_ThenTokensAreEmpty() {
        let query = "  \t\n\t\t \t \t  \n\n\n "
        let tokens = Score.tokens(from: query)

        XCTAssertEqual(tokens.count, 0)
    }

    func testWhenQueryContainsTabsOrNewlines_ThenResultIsTheSameAsIfThereAreSpaces() {
        let spaceQuery = "testing query tokens"
        let tabQuery = "testing\tquery\ttokens"
        let newlineQuery = "testing\nquery\ntokens"
        let spaceTokens = Score.tokens(from: spaceQuery)
        let tabTokens = Score.tokens(from: tabQuery)
        let newlineTokens = Score.tokens(from: newlineQuery)

        XCTAssertEqual(spaceTokens, ["testing", "query", "tokens"])
        XCTAssertEqual(spaceTokens, tabTokens)
        XCTAssertEqual(spaceTokens, newlineTokens)
    }
    
}
