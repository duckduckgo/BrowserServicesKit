//
//  APIRequestV2Tests.swift
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
import TestUtils

// final class APIRequestV2Tests: XCTestCase {
//
//    // NOTE: There's virtually no way to create an invalid APIRequest, any failure will be at fetch time
//
//    func testValidAPIRequest() throws {
//        let request = APIRequestV2(url: HTTPURLResponse.testUrl,
//                                   queryParameters: [
//                                    URLQueryItem(name: "test", value: "1"),
//                                    URLQueryItem(name: "another", value: "2")
//                                   ])
//        XCTAssertNotNil(request, "Valid request is nil")
//        XCTAssertEqual(request?.urlRequest.url?.absoluteString, "http://www.example.com?test=1&another=2")
//    }
// }

final class APIRequestV2Tests: XCTestCase {

    func testInitializationWithValidURL() {
        let url = URL(string: "https://www.example.com")!
        let method = HTTPRequestMethod.get
        let queryParameters: [URLQueryItem] = [URLQueryItem(name: "key", value: "value")]
        let headers = APIRequestV2.HeadersV2()
        let body = "Test body".data(using: .utf8)
        let timeoutInterval: TimeInterval = 30.0
        let cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
        let requirements: [APIResponseRequirementV2] = []

        let apiRequest = APIRequestV2(url: url,
                                      method: method,
                                      queryParameters: queryParameters,
                                      headers: headers,
                                      body: body,
                                      timeoutInterval: timeoutInterval,
                                      cachePolicy: cachePolicy,
                                      requirements: requirements)

        XCTAssertNotNil(apiRequest)
        XCTAssertEqual(apiRequest?.url, url)
        XCTAssertEqual(apiRequest?.method, method)
        XCTAssertEqual(apiRequest?.queryParameters, queryParameters)
        XCTAssertEqual(apiRequest?.headers, headers.httpHeaders)
        XCTAssertEqual(apiRequest?.body, body)
        XCTAssertEqual(apiRequest?.timeoutInterval, timeoutInterval)
        XCTAssertEqual(apiRequest?.cachePolicy, cachePolicy)
        XCTAssertEqual(apiRequest?.requirements, requirements)
    }

    func testURLRequestGeneration() {
        let url = URL(string: "https://www.example.com")!
        let method = HTTPRequestMethod.post
        let queryParameters: [URLQueryItem] = [URLQueryItem(name: "key", value: "value")]
        let headers = APIRequestV2.HeadersV2()
        let body = "Test body".data(using: .utf8)
        let timeoutInterval: TimeInterval = 30.0
        let cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData

        let apiRequest = APIRequestV2(url: url,
                                      method: method,
                                      queryParameters: queryParameters,
                                      headers: headers,
                                      body: body,
                                      timeoutInterval: timeoutInterval,
                                      cachePolicy: cachePolicy)

        XCTAssertNotNil(apiRequest)
        XCTAssertEqual(apiRequest?.urlRequest.url?.absoluteString, "https://www.example.com?key=value")
        XCTAssertEqual(apiRequest?.urlRequest.httpMethod, method.rawValue)
        XCTAssertEqual(apiRequest?.urlRequest.allHTTPHeaderFields, headers.httpHeaders)
        XCTAssertEqual(apiRequest?.urlRequest.httpBody, body)
        XCTAssertEqual(apiRequest?.urlRequest.timeoutInterval, timeoutInterval)
        XCTAssertEqual(apiRequest?.urlRequest.cachePolicy, cachePolicy)
    }

    func testDefaultValues() {
        let url = URL(string: "https://www.example.com")!
        let apiRequest = APIRequestV2(url: url)
        let headers = APIRequestV2.HeadersV2()

        XCTAssertNotNil(apiRequest)
        XCTAssertEqual(apiRequest?.method, .get)
        XCTAssertEqual(apiRequest?.timeoutInterval, 60.0)
        XCTAssertNil(apiRequest?.queryParameters)
        XCTAssertEqual(headers.httpHeaders, apiRequest?.headers)
        XCTAssertNil(apiRequest?.body)
        XCTAssertNil(apiRequest?.cachePolicy)
        XCTAssertNil(apiRequest?.requirements)
    }
}
