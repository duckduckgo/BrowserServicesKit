//
//  MockAPIService.swift
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

import Foundation
@testable import Networking

public class MockAPIService: APIService {

    public var authorizationRefresherCallback: AuthorizationRefresherCallback?

    // Dictionary to store predefined responses for specific requests
    private var mockResponses: [APIRequestV2: APIResponseV2] = [:]
    private var mockResponsesByURL: [URL: APIResponseV2] = [:]

    public init() {}

    public func set(response: APIResponseV2, forRequest request: APIRequestV2) {
        mockResponses[request] = response
    }

    public func set(response: APIResponseV2, forRequestURL url: URL) {
        mockResponsesByURL[url] = response
    }

    // Function to fetch response for a given request
    public func fetch(request: APIRequestV2) async throws -> APIResponseV2 {
        if let response = mockResponses[request] {
            return response
        }
        return mockResponsesByURL[request.urlRequest.url!]!
    }
}

public extension APIRequestV2 {
    var host: String {
        return urlRequest.url!.host!
    }
}
