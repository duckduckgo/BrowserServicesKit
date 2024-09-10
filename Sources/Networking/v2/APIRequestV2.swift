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

public struct APIRequestV2: CustomDebugStringConvertible {

    public typealias QueryItems = [String: String]

    let timeoutInterval: TimeInterval
    let requirements: [APIResponseRequirementV2]?
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
    ///   - responseRequirements: The request requirements
    ///   - allowedQueryReservedCharacters: The characters in this character set will not be URL encoded in the query parameters
    public init?(url: URL,
                 method: HTTPRequestMethod = .get,
                 queryItems: QueryItems? = nil,
                 headers: APIRequestV2.HeadersV2? = APIRequestV2.HeadersV2(),
                 body: Data? = nil,
                 timeoutInterval: TimeInterval = 60.0,
                 cachePolicy: URLRequest.CachePolicy? = nil,
                 responseRequirements: [APIResponseRequirementV2]? = nil,
                 allowedQueryReservedCharacters: CharacterSet? = nil) {
        self.timeoutInterval = timeoutInterval
        self.requirements = responseRequirements

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
    }

    public var debugDescription: String {
        """
        \(urlRequest.httpMethod ?? "Nil") \(urlRequest.url?.absoluteString ?? "nil")
        Headers: \(urlRequest.allHTTPHeaderFields?.debugDescription ?? "-")
        Body: \(urlRequest.httpBody?.debugDescription ?? "-")
        Requirements: \(requirements?.debugDescription ?? "-")
        """
    }
}
