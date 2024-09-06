//
//  APIRequestConfigurationV2.swift
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

public extension APIRequestV2 {

    struct ConfigurationV2: CustomDebugStringConvertible {

        public typealias QueryParams = [URLQueryItem]
        
        let url: URL
        let method: HTTPRequestMethod
        let queryParameters: QueryParams?
        let headers: HTTPHeaders
        let body: Data?
        let timeoutInterval: TimeInterval
        let cachePolicy: URLRequest.CachePolicy?

        public init(url: URL,
                    method: HTTPRequestMethod = .get,
                    queryParameters: QueryParams? = nil,
                    headers: APIRequest.Headers = APIRequest.Headers(),
                    body: Data? = nil,
                    timeoutInterval: TimeInterval = 60.0,
                    cachePolicy: URLRequest.CachePolicy? = nil) {
            self.url = url
            self.method = method
            self.queryParameters = queryParameters
            self.headers = headers.httpHeaders
            self.body = body
            self.timeoutInterval = timeoutInterval
            self.cachePolicy = cachePolicy
        }

        public var urlRequest: URLRequest? {
            guard var urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                return nil
            }
            urlComps.queryItems = queryParameters
            guard let finalURL = urlComps.url else {
                return nil
            }
            var request = URLRequest(url: finalURL, timeoutInterval: timeoutInterval)
            request.allHTTPHeaderFields = headers
            request.httpMethod = method.rawValue
            request.httpBody = body
            if let cachePolicy = cachePolicy {
                request.cachePolicy = cachePolicy
            }
            return request
        }

        public var debugDescription: String {
            """
            \(method.rawValue) \(urlRequest?.url?.absoluteString ?? "nil")
            Query params: \(queryParameters?.debugDescription ?? "-")
            Headers: \(headers)
            Body: \(body?.debugDescription ?? "-")
            """
        }
    }
}
