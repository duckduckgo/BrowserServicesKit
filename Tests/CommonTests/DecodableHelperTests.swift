//
//  DecodableHelperTests.swift
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
@testable import Common

final class DecodableHelperTests: XCTestCase {
    struct Person: Codable {
        let name: String
    }

    func testWhenDecodingDictionary_ThenValueIsReturned() {
        let dictionary = ["name": "dax"]
        let person: Person? = DecodableHelper.decode(from: dictionary)
        XCTAssertEqual("dax", person?.name)
    }

    func testWhenDecodingAny_ThenValueIsReturned() {
        let data = ["name": "dax"] as Any
        let person: Person? = DecodableHelper.decode(from: data)
        XCTAssertEqual("dax", person?.name)
    }

    func testWhenDecodingFails_ThenNilIsReturned() {
        let data = ["oops_name": "dax"] as Any
        let person: Person? = DecodableHelper.decode(from: data)
        XCTAssertNil(person)
    }
}
