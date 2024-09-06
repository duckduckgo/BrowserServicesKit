//
//  APIRequestV2Tests.swift
//  DuckDuckGo
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

    // NOTE: There's virtually no way to create an invalid APIRequest, any failure will be at fetch time

    func testValidAPIRequest() throws {
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl,
                                                         method: .get,
                                                         queryParameters: [
                                                            URLQueryItem(name: "test", value: "1"),
                                                            URLQueryItem(name: "another", value: "2")
                                                         ])
        let request = APIRequestV2(configuration: configuration)
        XCTAssertNotNil(request, "Valid request is nil")
        XCTAssertEqual(request?.urlRequest.url?.absoluteString, "http://www.example.com?test=1&another=2")
    }
}
