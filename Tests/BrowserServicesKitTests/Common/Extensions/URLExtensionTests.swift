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

    func test_external_urls_are_valid() {
        XCTAssertTrue("mailto://user@host.tld".url!.isValid)
        XCTAssertTrue("sms://+44776424232323".url!.isValid)
        XCTAssertTrue("ftp://example.com".url!.isValid)
    }

    func test_navigational_urls_are_valid() {
        XCTAssertTrue("http://example.com".url!.isValid)
        XCTAssertTrue("https://example.com".url!.isValid)
        XCTAssertTrue("http://localhost".url!.isValid)
        XCTAssertTrue("http://localdomain".url!.isValid)
    }

    func test_when_no_scheme_in_string_url_has_scheme() {
        XCTAssertEqual("duckduckgo.com".url!.absoluteString, "http://duckduckgo.com")
        XCTAssertEqual("example.com".url!.absoluteString, "http://example.com")
        XCTAssertEqual("localhost".url!.absoluteString, "http://localhost")
        XCTAssertNil("localdomain".url)
    }

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

    func testWhenPunycodeUrlIsCalledOnEmptyStringThenUrlIsNotReturned() {
        XCTAssertNil(URL(trimmedAddressBarString: "")?.absoluteString)
    }

    func testWhenPunycodeUrlIsCalledOnQueryThenUrlIsNotReturned() {
        XCTAssertNil(URL(trimmedAddressBarString: " ")?.absoluteString)
    }

    func testWhenPunycodeUrlIsCalledOnQueryWithSpaceThenUrlIsNotReturned() {
        XCTAssertNil(URL(trimmedAddressBarString: "https://www.duckduckgo .com/html?q=search")?.absoluteString)
        XCTAssertNil(URL(trimmedAddressBarString: "https://www.duckduckgo.com/html?q =search")?.absoluteString)
    }

    func testWhenPunycodeUrlIsCalledOnLocalHostnameThenUrlIsNotReturned() {
        XCTAssertNil(URL(trimmedAddressBarString: "💩")?.absoluteString)
    }

    func testWhenDefineSearchRequestIsMadeItIsNotInterpretedAsLocalURL() {
        XCTAssertNil(URL(trimmedAddressBarString: "define:300/spartans")?.absoluteString)
    }

    func testAddressBarURLParsing() {
        let addresses = [
            "user@somehost.local:9091/index.html",
            "something.local:9100",
            "user@localhost:5000",
            "user:password@localhost:5000",
            "localhost",
            "localhost:5000",
            "sms://+44123123123",
            "mailto:test@example.com",
            "https://",
            "http://duckduckgo.com",
            "https://duckduckgo.com",
            "https://duckduckgo.com/",
            "duckduckgo.com",
            "duckduckgo.com/html?q=search",
            "www.duckduckgo.com",
            "https://www.duckduckgo.com/html?q=search",
            "https://www.duckduckgo.com/html/?q=search",
            "ftp://www.duckduckgo.com",
            "file:///users/user/Documents/afile"
        ]

        for address in addresses {
            let url = URL(trimmedAddressBarString: address)
            var expectedString = address
            let expectedScheme = address.split(separator: "/").first.flatMap {
                $0.hasSuffix(":") ? String($0).dropping(suffix: ":") : nil
            }?.lowercased() ?? "http"
            if !address.hasPrefix(expectedScheme) {
                expectedString = expectedScheme + "://" + address
            }
            XCTAssertEqual(url?.scheme, expectedScheme)
            XCTAssertEqual(url?.absoluteString, expectedString)
        }
    }

    func testWhenPunycodeUrlIsCalledWithEncodedUrlsThenUrlIsReturned() {
        XCTAssertEqual("http://xn--ls8h.la", "💩.la".decodedURL?.absoluteString)
        XCTAssertEqual("http://xn--ls8h.la/", "💩.la/".decodedURL?.absoluteString)
        XCTAssertEqual("http://82.xn--b1aew.xn--p1ai", "82.мвд.рф".decodedURL?.absoluteString)
        XCTAssertEqual("http://xn--ls8h.la:8080", "http://💩.la:8080".decodedURL?.absoluteString)
        XCTAssertEqual("http://xn--ls8h.la", "http://💩.la".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la", "https://💩.la".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la/", "https://💩.la/".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la/path/to/resource", "https://💩.la/path/to/resource".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la/path/to/resource?query=true", "https://💩.la/path/to/resource?query=true".decodedURL?.absoluteString)
        XCTAssertEqual("https://xn--ls8h.la/%F0%9F%92%A9", "https://💩.la/💩".decodedURL?.absoluteString)
    }

}

private extension String {
    var url: URL? {
        return URL(trimmedAddressBarString: self)
    }
    var decodedURL: URL? {
        URL(trimmedAddressBarString: self)
    }
}
