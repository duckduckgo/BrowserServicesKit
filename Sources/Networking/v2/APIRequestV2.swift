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

import Foundation

public class APIRequestV2: CustomDebugStringConvertible {

    public struct RetryPolicy: CustomDebugStringConvertible {
        public let maxRetries: Int
        public let delay: TimeInterval

        public init(maxRetries: Int, delay: TimeInterval = 0) {
            self.maxRetries = maxRetries
            self.delay = delay
        }

        public var debugDescription: String {
            "MaxRetries: \(maxRetries), delay: \(delay)"
        }
    }

    public typealias QueryItems = [String: String]
    public var urlRequest: URLRequest
    internal let timeoutInterval: TimeInterval
    internal let responseConstraints: [APIResponseConstraints]?
    internal let retryPolicy: RetryPolicy?
    internal var authRefreshRetryCount: Int = 0
    internal var failureRetryCount: Int = 0

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
    public init?(url: URL,
                 method: HTTPRequestMethod = .get,
                 queryItems: QueryItems? = nil,
                 headers: APIRequestV2.HeadersV2? = APIRequestV2.HeadersV2(),
                 body: Data? = nil,
                 timeoutInterval: TimeInterval = 60.0,
                 retryPolicy: RetryPolicy? = nil,
                 cachePolicy: URLRequest.CachePolicy? = nil,
                 responseConstraints: [APIResponseConstraints]? = nil,
                 allowedQueryReservedCharacters: CharacterSet? = nil) {
        self.timeoutInterval = timeoutInterval
        self.responseConstraints = responseConstraints

        // Generate URL request
        guard var urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }
        urlComps.queryItems = queryItems?.toURLQueryItems(allowedReservedCharacters: allowedQueryReservedCharacters)
        guard let finalURL = urlComps.url else {
            return nil
        }
        var request = URLRequest(url: finalURL, timeoutInterval: timeoutInterval)
        request.allHTTPHeaderFields = headers?.httpHeaders
        request.httpMethod = method.rawValue
        request.httpBody = body
        if let cachePolicy = cachePolicy {
            request.cachePolicy = cachePolicy
        }
        self.urlRequest = request
        self.retryPolicy = retryPolicy
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
        Retry Policy: \(retryPolicy?.debugDescription ?? "None")
        Retries counts: Refresh (\(authRefreshRetryCount), Failure (\(failureRetryCount))
        """
    }

    public func updateAuthorizationHeader(_ token: String) {
        self.urlRequest.allHTTPHeaderFields?[HTTPHeaderKey.authorization] = "Bearer \(token)"
    }

    public var isAuthenticated: Bool {
        return urlRequest.allHTTPHeaderFields?[HTTPHeaderKey.authorization] != nil
    }
}
