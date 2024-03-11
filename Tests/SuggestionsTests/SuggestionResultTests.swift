//
//  SuggestionResultTests.swift
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
@testable import Suggestions

final class SuggestionResultTests: XCTestCase {

    func testWhenResultContainsNoSuggestions_ThenItIsEmpty() {
        let emptyResult = SuggestionResult.empty

        XCTAssert(emptyResult.isEmpty)
        XCTAssertEqual(emptyResult.topHits.count, 0)
        XCTAssertEqual(emptyResult.historyAndBookmarks.count, 0)
        XCTAssertEqual(emptyResult.duckduckgoSuggestions.count, 0)
    }

}
