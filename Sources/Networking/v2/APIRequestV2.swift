//
//  APIRequestV2.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Common
import Foundation

public struct APIRequestV2: CustomDebugStringConvertible {

    let timeoutInterval: TimeInterval
    let responseConstraints: [APIResponseConstraints]?
    public let urlRequest: URLRequest

    /// Designated initialiser
    /// - Parameters:
    ///   - url: The request URL, included protocol and host
    ///   - method: HTTP method
    ///   - queryItems: A key value dictionary with query parameters
    ///   - headers: HTTP headers
    ///   - body: The request body
    ///   - timeoutInterval: The request timeout interval, default is `60`s
    ///   - cachePolicy: The request cache policy, default is `.useProtocolCachePolicy`
    ///   - responseRequirements: The response requirements
    ///   - allowedQueryReservedCharacters: The characters in this character set will not be URL encoded in the query parameters
    public init<QueryParams: Collection>(
        url: URL,
        method: HTTPRequestMethod = .get,
        queryItems: QueryParams?,
        headers: APIRequestV2.HeadersV2? = APIRequestV2.HeadersV2(),
        body: Data? = nil,
        timeoutInterval: TimeInterval = 60.0,
        cachePolicy: URLRequest.CachePolicy? = nil,
        responseConstraints: [APIResponseConstraints]? = nil,
        allowedQueryReservedCharacters: CharacterSet? = nil
    ) where QueryParams.Element == (key: String, value: String) {

        self.timeoutInterval = timeoutInterval
        self.responseConstraints = responseConstraints

        let finalURL = if let queryItems {
            url.appendingParameters(queryItems, allowedReservedCharacters: allowedQueryReservedCharacters)
        } else {
            url
        }
        var request = URLRequest(url: finalURL, timeoutInterval: timeoutInterval)
        request.allHTTPHeaderFields = headers?.httpHeaders
        request.httpMethod = method.rawValue
        request.httpBody = body
        if let cachePolicy = cachePolicy {
            request.cachePolicy = cachePolicy
        }
        self.urlRequest = request
    }

    public init(
        url: URL,
        method: HTTPRequestMethod = .get,
        headers: APIRequestV2.HeadersV2? = APIRequestV2.HeadersV2(),
        body: Data? = nil,
        timeoutInterval: TimeInterval = 60.0,
        cachePolicy: URLRequest.CachePolicy? = nil,
        responseConstraints: [APIResponseConstraints]? = nil,
        allowedQueryReservedCharacters: CharacterSet? = nil
    ) {
        self.init(url: url, method: method, queryItems: [String: String]?.none, headers: headers, body: body, timeoutInterval: timeoutInterval, cachePolicy: cachePolicy, responseConstraints: responseConstraints, allowedQueryReservedCharacters: allowedQueryReservedCharacters)
    }

    public var debugDescription: String {
        """
        APIRequestV2:
        URL: \(urlRequest.url?.absoluteString ?? "nil")
        Method: \(urlRequest.httpMethod ?? "nil")
        Headers: \(urlRequest.allHTTPHeaderFields?.debugDescription ?? "-")
        Body: \(urlRequest.httpBody?.debugDescription ?? "-")
        Timeout Interval: \(timeoutInterval)s
        Cache Policy: \(urlRequest.cachePolicy)
        Response Constraints: \(responseConstraints?.map { $0.rawValue } ?? [])
        """
    }
}
