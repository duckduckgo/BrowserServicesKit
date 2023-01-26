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
@testable import Common

// swiftlint:disable line_length
// swiftlint:disable type_body_length

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
        let url = URL(string: "https://duckduckgo.com/?q=Battle%20star+Galactica%25a")!

        XCTAssertEqual(
            url.appendingParameter(name: "ia", value: "web"),
            URL(string: "https://duckduckgo.com/?q=Battle%20star+Galactica%25a&ia=web")!
        )
    }

    func testWhenAddParameterIsCalled_ThenItEncodesRFC3986QueryReservedCharactersInTheParameter() {
        let url = URL(string: "https://duck.com/")!

        XCTAssertEqual(url.appendingParameter(name: ":", value: ":"), URL(string: "https://duck.com/?%3A=%3A")!)
        XCTAssertEqual(url.appendingParameter(name: "/", value: "/"), URL(string: "https://duck.com/?%2F=%2F")!)
        XCTAssertEqual(url.appendingParameter(name: "?", value: "?"), URL(string: "https://duck.com/?%3F=%3F")!)
        XCTAssertEqual(url.appendingParameter(name: "#", value: "#"), URL(string: "https://duck.com/?%23=%23")!)
        XCTAssertEqual(url.appendingParameter(name: "[", value: "["), URL(string: "https://duck.com/?%5B=%5B")!)
        XCTAssertEqual(url.appendingParameter(name: "]", value: "]"), URL(string: "https://duck.com/?%5D=%5D")!)
        XCTAssertEqual(url.appendingParameter(name: "@", value: "@"), URL(string: "https://duck.com/?%40=%40")!)
        XCTAssertEqual(url.appendingParameter(name: "!", value: "!"), URL(string: "https://duck.com/?%21=%21")!)
        XCTAssertEqual(url.appendingParameter(name: "$", value: "$"), URL(string: "https://duck.com/?%24=%24")!)
        XCTAssertEqual(url.appendingParameter(name: "&", value: "&"), URL(string: "https://duck.com/?%26=%26")!)
        XCTAssertEqual(url.appendingParameter(name: "'", value: "'"), URL(string: "https://duck.com/?%27=%27")!)
        XCTAssertEqual(url.appendingParameter(name: "(", value: "("), URL(string: "https://duck.com/?%28=%28")!)
        XCTAssertEqual(url.appendingParameter(name: ")", value: ")"), URL(string: "https://duck.com/?%29=%29")!)
        XCTAssertEqual(url.appendingParameter(name: "*", value: "*"), URL(string: "https://duck.com/?%2A=%2A")!)
        XCTAssertEqual(url.appendingParameter(name: "+", value: "+"), URL(string: "https://duck.com/?%2B=%2B")!)
        XCTAssertEqual(url.appendingParameter(name: ",", value: ","), URL(string: "https://duck.com/?%2C=%2C")!)
        XCTAssertEqual(url.appendingParameter(name: ";", value: ";"), URL(string: "https://duck.com/?%3B=%3B")!)
        XCTAssertEqual(url.appendingParameter(name: "=", value: "="), URL(string: "https://duck.com/?%3D=%3D")!)
    }

    func testWhenAddParameterIsCalled_ThenItAllowsUnescapedReservedCharactersAsSpecified() {
        let url = URL(string: "https://duck.com/")!

        XCTAssertEqual(
            url.appendingParameter(
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

    func testWhenURLParametersModifiedWithInvalidCharactersThenParametersArePercentEscaped() {
        XCTAssertEqual(URL(trimmedAddressBarString: "https://www.duckduckgo.com/html?q=a%20search with+space?+and%25plus&ia=calculator")!.absoluteString,
                       "https://www.duckduckgo.com/html?q=a%20search%20with+space?+and%25plus&ia=calculator")
    }

    func testWhenURLWithEmptyQueryIsFixedUpThenQuestionCharIsKept() {
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/?")!.absoluteString,
                       "https://duckduckgo.com/?")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com?")!.absoluteString,
                       "https://duckduckgo.com?")
        XCTAssertEqual(URL(trimmedAddressBarString: "https:/duckduckgo.com/?")!.absoluteString,
                       "https://duckduckgo.com/?")
        XCTAssertEqual(URL(trimmedAddressBarString: "https:/duckduckgo.com?")!.absoluteString,
                       "https://duckduckgo.com?")
    }

    func testWhenURLWithHashIsFixedUpThenHashIsCorrectlyEscaped() {
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/#hash with #")!.absoluteString,
                       "https://duckduckgo.com/#hash%20with%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q=a b#hash with #")!.absoluteString,
                       "https://duckduckgo.com/html?q=a%20b#hash%20with%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html#hash with #")!.absoluteString,
                       "https://duckduckgo.com/html#hash%20with%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q#hash with #")!.absoluteString,
                       "https://duckduckgo.com/html?q#hash%20with%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html?#hash with? #")!.absoluteString,
                       "https://duckduckgo.com/html?#hash%20with?%20%23")
        XCTAssertEqual(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q=a b#")!.absoluteString,
                       "https://duckduckgo.com/html?q=a%20b#")
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

    func testWhenParamExistsThengetParameterReturnsCorrectValue() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")
        let expected = "secondValue"
        let actual = url?.getParameter(named: "secondParam")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamDoesNotExistThengetParameterIsNil() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")
        let result = url?.getParameter(named: "someOtherParam")
        XCTAssertNil(result)
    }

    func testWhenParamExistsThenRemovingReturnUrlWithoutParam() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")
        let expected = URL(string: "http://test.com?secondParam=secondValue")
        let actual = url?.removeParameter(name: "firstParam")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamDoesNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")
        let actual = url?.removeParameter(name: "someOtherParam")
        XCTAssertEqual(actual, url)
    }

    func testWhenRemovingAParamThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")
        let actual = url?.removeParameter(name: "firstParam")
        XCTAssertEqual(actual, expected)
    }

    func testWhenRemovingParamsThenRemovingReturnsUrlWithoutParams() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue&thirdParam=thirdValue")
        let expected = URL(string: "http://test.com?secondParam=secondValue")
        let actual = url?.removingParameters(named: ["firstParam", "thirdParam"])
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamsDoNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")
        let actual = url?.removingParameters(named: ["someParam", "someOtherParam"])
        XCTAssertEqual(actual, url)
    }

    func testWhenEmptyParamArrayIsUsedThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")
        let actual = url?.removingParameters(named: [])
        XCTAssertEqual(actual, url)
    }

    func testWhenRemovingParamsThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")
        let actual = url?.removingParameters(named: ["firstParam"])
        XCTAssertEqual(actual, expected)
    }

    func testWhenNoParamsThenAddingAppendsQuery() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=aValue")!
        let actual = url.appendingParameter(name: "aParam", value: "aValue")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamDoesNotExistThenAddingParamAppendsItToExistingQuery() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")!
        let expected = URL(string: "http://test.com?firstParam=firstValue&anotherParam=anotherValue")!
        let actual = url.appendingParameter(name: "anotherParam", value: "anotherValue")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamHasInvalidCharactersThenAddingParamAppendsEncodedVersion() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=43%20%2B%205")!
        let actual = url.appendingParameter(name: "aParam", value: "43 + 5")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamExistsThenAddingNewValueAppendsParam() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")!
        let expected = URL(string: "http://test.com?firstParam=firstValue&firstParam=newValue")!
        let actual = url.appendingParameter(name: "firstParam", value: "newValue")
        XCTAssertEqual(actual, expected)
    }

    func testMatchesComparator() {
        XCTAssertTrue("youtube.com".url!.matches("http://youtube.com".url!))
        XCTAssertTrue("youtube.com/".url!.matches("http://youtube.com".url!))
        XCTAssertTrue("youtube.com".url!.matches("http://youtube.com/".url!))
        XCTAssertTrue("youtube.com/".url!.matches("http://youtube.com/".url!))
        XCTAssertTrue("http://youtube.com/".url!.matches("youtube.com".url!))
        XCTAssertTrue("http://youtube.com".url!.matches("youtube.com/".url!))
        XCTAssertTrue("https://youtube.com/".url!.matches("https://youtube.com".url!))
        XCTAssertTrue("https://youtube.com/#link#1".url!.matches("https://youtube.com#link#1".url!))
        XCTAssertTrue("https://youtube.com/#link#1".url!.matches("https://youtube.com#link#1".url!))
        XCTAssertTrue("https://youtube.com/#link#1".url!.matches("https://youtube.com/#link#1".url!))
        XCTAssertTrue("https://youtube.com#link#1".url!.matches("https://youtube.com/#link#1".url!))

        XCTAssertFalse("youtube.com".url!.matches("https://youtube.com".url!))
        XCTAssertFalse("youtube.com/".url!.matches("https://youtube.com".url!))
        XCTAssertFalse("youtube.com/#link#1".url!.matches("https://youtube.com#link#2".url!))
        XCTAssertFalse("youtube.com/#link#1".url!.matches("https://youtube.com#link".url!))
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

extension URL {
    func removeParameter(name: String) -> URL {
        return self.removingParameters(named: [name])
    }
}
