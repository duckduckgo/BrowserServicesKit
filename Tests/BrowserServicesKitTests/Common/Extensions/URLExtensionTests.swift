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

    func testWhenRootIsCalled_ThenURLWithNoPathQueryFragmentUserAndPasswordIsReturned() {
        let url = URL(string: "https://dax:123456@www.duckduckgo.com/test.php?test=S&info=test#fragment")!

        let rootUrl = url.root!
        XCTAssertEqual(rootUrl, URL(string: "https://www.duckduckgo.com/")!)
        XCTAssert(rootUrl.isRoot)
    }

    func testIsRoot() {
        let url = URL(string: "https://www.server.com:8080/path?query=string#fragment")!
        let rootUrl = URL(string: "https://www.server.com:8080/")!

        XCTAssert(rootUrl.isRoot)
        XCTAssertFalse(url.isRoot)
    }

    func testWhenAddParameterIsCalled_ThenItDoesNotChangeExistingURL() {
        let url = URL(string: "https://duckduckgo.com/?q=Battlestar+Galactica")!

        XCTAssertEqual(
            try url.addParameter(name: "ia", value: "web"),
            URL(string: "https://duckduckgo.com/?q=Battlestar+Galactica&ia=web")!
        )
    }

    func testWhenAddParameterIsCalled_ThenItEncodesRFC3986QueryReservedCharactersInTheParameter() {
        let url = URL(string: "https://duck.com/")!

        XCTAssertEqual(try url.addParameter(name: ":", value: ":"), URL(string: "https://duck.com/?%3A=%3A")!)
        XCTAssertEqual(try url.addParameter(name: "/", value: "/"), URL(string: "https://duck.com/?%2F=%2F")!)
        XCTAssertEqual(try url.addParameter(name: "?", value: "?"), URL(string: "https://duck.com/?%3F=%3F")!)
        XCTAssertEqual(try url.addParameter(name: "#", value: "#"), URL(string: "https://duck.com/?%23=%23")!)
        XCTAssertEqual(try url.addParameter(name: "[", value: "["), URL(string: "https://duck.com/?%5B=%5B")!)
        XCTAssertEqual(try url.addParameter(name: "]", value: "]"), URL(string: "https://duck.com/?%5D=%5D")!)
        XCTAssertEqual(try url.addParameter(name: "@", value: "@"), URL(string: "https://duck.com/?%40=%40")!)
        XCTAssertEqual(try url.addParameter(name: "!", value: "!"), URL(string: "https://duck.com/?%21=%21")!)
        XCTAssertEqual(try url.addParameter(name: "$", value: "$"), URL(string: "https://duck.com/?%24=%24")!)
        XCTAssertEqual(try url.addParameter(name: "&", value: "&"), URL(string: "https://duck.com/?%26=%26")!)
        XCTAssertEqual(try url.addParameter(name: "'", value: "'"), URL(string: "https://duck.com/?%27=%27")!)
        XCTAssertEqual(try url.addParameter(name: "(", value: "("), URL(string: "https://duck.com/?%28=%28")!)
        XCTAssertEqual(try url.addParameter(name: ")", value: ")"), URL(string: "https://duck.com/?%29=%29")!)
        XCTAssertEqual(try url.addParameter(name: "*", value: "*"), URL(string: "https://duck.com/?%2A=%2A")!)
        XCTAssertEqual(try url.addParameter(name: "+", value: "+"), URL(string: "https://duck.com/?%2B=%2B")!)
        XCTAssertEqual(try url.addParameter(name: ",", value: ","), URL(string: "https://duck.com/?%2C=%2C")!)
        XCTAssertEqual(try url.addParameter(name: ";", value: ";"), URL(string: "https://duck.com/?%3B=%3B")!)
        XCTAssertEqual(try url.addParameter(name: "=", value: "="), URL(string: "https://duck.com/?%3D=%3D")!)
    }

    func testWhenAddParameterIsCalled_ThenItAllowsUnescapedReservedCharactersAsSpecified() {
        let url = URL(string: "https://duck.com/")!

        XCTAssertEqual(
            try url.addParameter(
                name: "domains",
                value: "test.com,example.com/test,localhost:8000/api",
                allowedReservedCharacters: .init(charactersIn: ",:")
            ),
            URL(string: "https://duck.com/?domains=test.com,example.com%2Ftest,localhost:8000%2Fapi")!
        )
    }
}
