//
//  URLExtensionTests.swift
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

final class URLExtensionTests: XCTestCase {

    func testWhenNakedIsCalled_ThenURLWithNoSchemeWWWPrefixAndLastSlashIsReturned() {
        let url = URL(string: "http://duckduckgo.com")!
        let duplicate = URL(string: "https://www.duckduckgo.com/")!

        XCTAssertEqual(url.naked, duplicate.naked)
    }

    func testWhenRootIsCalled_ThenURLWithRootPathAndWithoutQueryOrFragmentIsReturend() {
        let url = URL(string: "https://www.server.com:8080/path?query=string#fragment")!
        let rootUrl = URL(string: "https://www.server.com:8080/")!

        XCTAssertEqual(url.root, rootUrl)
        XCTAssert(rootUrl.isRoot)
        XCTAssert(url.root!.isRoot)
    }

}
