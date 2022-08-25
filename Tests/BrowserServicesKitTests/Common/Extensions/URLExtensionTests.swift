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
            try url.appendingParameter(name: "ia", value: "web"),
            URL(string: "https://duckduckgo.com/?q=Battlestar+Galactica&ia=web")!
        )
    }

    func testWhenAddParameterIsCalled_ThenItEncodesRFC3986QueryReservedCharactersInTheParameter() {
        let url = URL(string: "https://duck.com/")!

        XCTAssertEqual(try url.appendingParameter(name: ":", value: ":"), URL(string: "https://duck.com/?%3A=%3A")!)
        XCTAssertEqual(try url.appendingParameter(name: "/", value: "/"), URL(string: "https://duck.com/?%2F=%2F")!)
        XCTAssertEqual(try url.appendingParameter(name: "?", value: "?"), URL(string: "https://duck.com/?%3F=%3F")!)
        XCTAssertEqual(try url.appendingParameter(name: "#", value: "#"), URL(string: "https://duck.com/?%23=%23")!)
        XCTAssertEqual(try url.appendingParameter(name: "[", value: "["), URL(string: "https://duck.com/?%5B=%5B")!)
        XCTAssertEqual(try url.appendingParameter(name: "]", value: "]"), URL(string: "https://duck.com/?%5D=%5D")!)
        XCTAssertEqual(try url.appendingParameter(name: "@", value: "@"), URL(string: "https://duck.com/?%40=%40")!)
        XCTAssertEqual(try url.appendingParameter(name: "!", value: "!"), URL(string: "https://duck.com/?%21=%21")!)
        XCTAssertEqual(try url.appendingParameter(name: "$", value: "$"), URL(string: "https://duck.com/?%24=%24")!)
        XCTAssertEqual(try url.appendingParameter(name: "&", value: "&"), URL(string: "https://duck.com/?%26=%26")!)
        XCTAssertEqual(try url.appendingParameter(name: "'", value: "'"), URL(string: "https://duck.com/?%27=%27")!)
        XCTAssertEqual(try url.appendingParameter(name: "(", value: "("), URL(string: "https://duck.com/?%28=%28")!)
        XCTAssertEqual(try url.appendingParameter(name: ")", value: ")"), URL(string: "https://duck.com/?%29=%29")!)
        XCTAssertEqual(try url.appendingParameter(name: "*", value: "*"), URL(string: "https://duck.com/?%2A=%2A")!)
        XCTAssertEqual(try url.appendingParameter(name: "+", value: "+"), URL(string: "https://duck.com/?%2B=%2B")!)
        XCTAssertEqual(try url.appendingParameter(name: ",", value: ","), URL(string: "https://duck.com/?%2C=%2C")!)
        XCTAssertEqual(try url.appendingParameter(name: ";", value: ";"), URL(string: "https://duck.com/?%3B=%3B")!)
        XCTAssertEqual(try url.appendingParameter(name: "=", value: "="), URL(string: "https://duck.com/?%3D=%3D")!)
    }

    func testWhenAddParameterIsCalled_ThenItAllowsUnescapedReservedCharactersAsSpecified() {
        let url = URL(string: "https://duck.com/")!

        XCTAssertEqual(
            try url.appendingParameter(
                name: "domains",
                value: "test.com,example.com/test,localhost:8000/api",
                allowedReservedCharacters: .init(charactersIn: ",:")
            ),
            URL(string: "https://duck.com/?domains=test.com,example.com%2Ftest,localhost:8000%2Fapi")!
        )
    }

    func testWhenParamExistsThengetParameterReturnsCorrectValue() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")
        let expected = "secondValue"
        let actual = try url?.getParameter(name: "secondParam")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamDoesNotExistThengetParameterIsNil() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")
        let result = try url?.getParameter(name: "someOtherParam")
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

    func testWhenRemovingAParamThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces_bugFix() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")
        let expected = URL(string: "http://test.com?secondParam=45%20+%205")
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

    func testWhenRemovingParamsThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces_bugFix() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")
        let expected = URL(string: "http://test.com?secondParam=45%20+%205")
        let actual = url?.removingParameters(named: ["firstParam"])
        XCTAssertEqual(actual, expected)
    }

    func testWhenNoParamsThenAddingAppendsQuery() throws {
        let url = URL(string: "http://test.com")
        let expected = URL(string: "http://test.com?aParam=aValue")
        let actual = try url?.appendingParameter(name: "aParam", value: "aValue")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamDoesNotExistThenAddingParamAppendsItToExistingQuery() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")
        let expected = URL(string: "http://test.com?firstParam=firstValue&anotherParam=anotherValue")
        let actual = try url?.appendingParameter(name: "anotherParam", value: "anotherValue")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamHasInvalidCharactersThenAddingParamAppendsEncodedVersion() throws {
        let url = URL(string: "http://test.com")
        let expected = URL(string: "http://test.com?aParam=43%20%2B%205")
        let actual = try url?.appendingParameter(name: "aParam", value: "43 + 5")
        XCTAssertEqual(actual, expected)
    }

    func testWhenParamExistsThenAddingNewValueUpdatesParam() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")
        let expected = URL(string: "http://test.com?firstParam=newValue")
        let actual = try url?.appendingParameter(name: "firstParam", value: "newValue")
        XCTAssertEqual(actual, expected)
    }

}

extension URL {
    func removeParameter(name: String) -> URL {
        return self.removingParameters(named: [name])
    }
}
