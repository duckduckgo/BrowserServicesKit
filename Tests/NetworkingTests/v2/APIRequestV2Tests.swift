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

final class APIRequestV2Tests: XCTestCase {

    func testInitializationWithValidURL() {
        let url = URL(string: "https://www.example.com")!
        let method = HTTPRequestMethod.get
        let queryItems = ["key": "value"]
        let headers = APIRequestV2.HeadersV2()
        let body = "Test body".data(using: .utf8)
        let timeoutInterval: TimeInterval = 30.0
        let cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
        let constraints: [APIResponseConstraints] = []

        let apiRequest = APIRequestV2(url: url,
                                      method: method,
                                      queryItems: queryItems,
                                      headers: headers,
                                      body: body,
                                      timeoutInterval: timeoutInterval,
                                      cachePolicy: cachePolicy,
                                      responseConstraints: constraints)

        let urlRequest = apiRequest.urlRequest
        XCTAssertEqual(urlRequest.url?.host(), url.host())
        XCTAssertEqual(urlRequest.httpMethod, method.rawValue)

        let urlComponents = URLComponents(string: urlRequest.url!.absoluteString)!
        XCTAssertTrue(urlComponents.queryItems!.contains(URLQueryItem(name: "key", value: "value")))

        XCTAssertEqual(urlRequest.allHTTPHeaderFields, headers.httpHeaders)
        XCTAssertEqual(urlRequest.httpBody, body)
        XCTAssertEqual(apiRequest.timeoutInterval, timeoutInterval)
        XCTAssertEqual(urlRequest.cachePolicy, cachePolicy)
        XCTAssertEqual(apiRequest.responseConstraints, constraints)
    }

    func testURLRequestGeneration() {
        let url = URL(string: "https://www.example.com")!
        let method = HTTPRequestMethod.post
        let queryItems = ["key": "value"]
        let headers = APIRequestV2.HeadersV2()
        let body = "Test body".data(using: .utf8)
        let timeoutInterval: TimeInterval = 30.0
        let cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData

        let apiRequest = APIRequestV2(url: url,
                                      method: method,
                                      queryItems: queryItems,
                                      headers: headers,
                                      body: body,
                                      timeoutInterval: timeoutInterval,
                                      cachePolicy: cachePolicy)

        let urlComponents = URLComponents(string: apiRequest.urlRequest.url!.absoluteString)!
        XCTAssertTrue(urlComponents.queryItems!.contains(URLQueryItem(name: "key", value: "value")))

        XCTAssertNotNil(apiRequest)
        XCTAssertEqual(apiRequest.urlRequest.url?.absoluteString, "https://www.example.com?key=value")
        XCTAssertEqual(apiRequest.urlRequest.httpMethod, method.rawValue)
        XCTAssertEqual(apiRequest.urlRequest.allHTTPHeaderFields, headers.httpHeaders)
        XCTAssertEqual(apiRequest.urlRequest.httpBody, body)
        XCTAssertEqual(apiRequest.urlRequest.timeoutInterval, timeoutInterval)
        XCTAssertEqual(apiRequest.urlRequest.cachePolicy, cachePolicy)
    }

    func testDefaultValues() {
        let url = URL(string: "https://www.example.com")!
        let apiRequest = APIRequestV2(url: url)
        let headers = APIRequestV2.HeadersV2()

        let urlRequest = apiRequest.urlRequest
        XCTAssertEqual(urlRequest.httpMethod, HTTPRequestMethod.get.rawValue)
        XCTAssertEqual(urlRequest.timeoutInterval, 60.0)
        XCTAssertEqual(headers.httpHeaders, urlRequest.allHTTPHeaderFields)
        XCTAssertNil(urlRequest.httpBody)
        XCTAssertEqual(urlRequest.cachePolicy.rawValue, 0)
        XCTAssertNil(apiRequest.responseConstraints)
    }

    func testAllowedQueryReservedCharacters() {
        let url = URL(string: "https://www.example.com")!
        let queryItems = ["k#e,y": "val#ue"]

        let apiRequest = APIRequestV2(url: url,
                                      queryItems: queryItems,
                                      allowedQueryReservedCharacters: CharacterSet(charactersIn: ","))

        let urlString = apiRequest.urlRequest.url!.absoluteString
        XCTAssertEqual(urlString, "https://www.example.com?k%23e,y=val%23ue")

        let urlComponents = URLComponents(string: urlString)!
        XCTAssertEqual(urlComponents.queryItems?.count, 1)
    }
}
