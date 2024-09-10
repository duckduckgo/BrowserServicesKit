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
    public typealias QueryParams = [URLQueryItem]

    let url: URL
    let method: HTTPRequestMethod
    let queryParameters: QueryParams?
    let headers: HTTPHeaders?
    let body: Data?
    let timeoutInterval: TimeInterval
    let cachePolicy: URLRequest.CachePolicy?
    let requirements: [APIResponseRequirementV2]?
    public let urlRequest: URLRequest

    public init?(url: URL,
                 method: HTTPRequestMethod = .get,
                 queryParameters: QueryParams? = nil,
                 headers: APIRequestV2.HeadersV2? = APIRequestV2.HeadersV2(),
                 body: Data? = nil,
                 timeoutInterval: TimeInterval = 60.0,
                 cachePolicy: URLRequest.CachePolicy? = nil,
                 requirements: [APIResponseRequirementV2]? = nil) {
        self.url = url
        self.method = method
        self.queryParameters = queryParameters
        self.headers = headers?.httpHeaders
        self.body = body
        self.timeoutInterval = timeoutInterval
        self.cachePolicy = cachePolicy
        self.requirements = requirements

        // Generate URL request
        guard var urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }
        urlComps.queryItems = queryParameters
        guard let finalURL = urlComps.url else {
            return nil
        }
        var request = URLRequest(url: finalURL, timeoutInterval: timeoutInterval)
        request.allHTTPHeaderFields = self.headers
        request.httpMethod = self.method.rawValue
        request.httpBody = body
        if let cachePolicy = cachePolicy {
            request.cachePolicy = cachePolicy
        }
        self.urlRequest = request
    }

    public var debugDescription: String {
        """
        \(method.rawValue) \(urlRequest.url?.absoluteString ?? "nil")
        Headers: \(headers?.debugDescription ?? "-")
        Body: \(body?.debugDescription ?? "-")
        Requirements: \(requirements?.debugDescription ?? "-")
        """
    }
}
