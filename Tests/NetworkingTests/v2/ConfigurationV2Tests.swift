//
//  ConfigurationV2Tests.swift
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

import XCTest
@testable import Networking

final class ConfigurationV2Tests: XCTestCase {

    func testInitializationWithDefaultValues() {
        let url = URL(string: "https://example.com")!
        let config = APIRequestV2.ConfigurationV2(url: url)

        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.method, .get)
        XCTAssertNil(config.queryParameters)
        XCTAssertEqual(config.headers?[HTTPHeaderKey.acceptLanguage], "en-GB;q=1.0, it-IT;q=0.9")
        XCTAssertEqual(config.headers?[HTTPHeaderKey.userAgent], "")
        XCTAssertEqual(config.headers?[HTTPHeaderKey.acceptEncoding], "gzip;q=1.0, compress;q=0.5")
        XCTAssertNil(config.body)
        XCTAssertEqual(config.timeoutInterval, 60.0)
        XCTAssertNil(config.cachePolicy)
    }

    func testInitializationWithCustomValues() {
        let url = URL(string: "https://example.com")!
        let headers = APIRequestV2.HeadersV2(userAgent: "a",
                                             etag: "b",
                                             additionalHeaders: [
                                                HTTPHeaderKey.acceptEncoding: "c"
                                             ])
        let bodyData = "test body".data(using: .utf8)
        let queryItems = [URLQueryItem(name: "key", value: "value")]

        let config = APIRequestV2.ConfigurationV2(
            url: url,
            method: .post,
            queryParameters: queryItems,
            headers: headers,
            body: bodyData,
            timeoutInterval: 120.0,
            cachePolicy: .reloadIgnoringLocalCacheData
        )

        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.method, .post)
        XCTAssertEqual(config.queryParameters, queryItems)
        XCTAssertEqual(config.headers?[HTTPHeaderKey.userAgent], "a")
        XCTAssertEqual(config.headers?[HTTPHeaderKey.etag], "b")
        XCTAssertEqual(config.headers?[HTTPHeaderKey.acceptEncoding], "c")
        XCTAssertEqual(config.body, bodyData)
        XCTAssertEqual(config.timeoutInterval, 120.0)
        XCTAssertEqual(config.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    // Test URLRequest generation
    func testURLRequestGeneration() {
        let url = URL(string: "https://example.com")!
        let queryItems = [URLQueryItem(name: "key", value: "value")]
        let headers = ["Authorization": "Bearer token"]
        let bodyData = "test body".data(using: .utf8)

        let config = APIRequestV2.ConfigurationV2(
            url: url,
            method: .post,
            queryParameters: queryItems,
            headers: nil,
            body: bodyData,
            timeoutInterval: 120.0,
            cachePolicy: .reloadIgnoringLocalCacheData
        )

        let urlRequest = config.urlRequest
        XCTAssertEqual(urlRequest?.url?.absoluteString, "https://example.com?key=value")
        XCTAssertEqual(urlRequest?.httpMethod, "POST")
        XCTAssertEqual(urlRequest?.allHTTPHeaderFields?["Authorization"], "Bearer token")
        XCTAssertEqual(urlRequest?.httpBody, bodyData)
        XCTAssertEqual(urlRequest?.timeoutInterval, 120.0)
        XCTAssertEqual(urlRequest?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    // Test URLRequest generation with nil queryParameters
    func testURLRequestWithoutQueryParameters() {
        let url = URL(string: "https://example.com")!

        let config = APIRequestV2.ConfigurationV2(
            url: url,
            method: .get,
            queryParameters: nil,
            body: nil,
            timeoutInterval: 60.0,
            cachePolicy: nil
        )

        let urlRequest = config.urlRequest
        XCTAssertEqual(urlRequest?.url?.absoluteString, "https://example.com")
        XCTAssertEqual(urlRequest?.httpMethod, "GET")
        XCTAssertEqual(urlRequest?.allHTTPHeaderFields?["Authorization"], "Bearer token")
        XCTAssertEqual(urlRequest?.timeoutInterval, 60.0)
        XCTAssertNil(urlRequest?.cachePolicy)
    }
}
