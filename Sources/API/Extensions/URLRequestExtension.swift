//
//  URLRequestExtension.swift
//  DuckDuckGo
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
import Common

extension URLRequest {

    public static func developerInitiated(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        
        if #available(iOS 15.0, macOS 12.0, *) {
            request.attribution = .developer
        }

        return request
    }
    
    public static func userInitiated(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)

        if #available(iOS 15.0, macOS 12.0, *) {
            request.attribution = .user
        }

        return request
    }
    
    // swiftlint:disable:next function_parameter_count
    public static func makeRequest<C: Collection>(url: URL,
                                                  method: HTTPMethod = .get,
                                                  parameters: C = [],
                                                  headers: HTTPHeaders,
                                                  httpBody: Data? = nil,
                                                  timeoutInterval: TimeInterval = 60.0) -> URLRequest
    where C.Element == (key: String, value: String) {
        let url = url.appendingParameters(parameters)
        var urlRequest = Self.developerInitiated(url)
        urlRequest.allHTTPHeaderFields = headers
        urlRequest.httpMethod = method.rawValue
        urlRequest.httpBody = httpBody
        urlRequest.timeoutInterval = timeoutInterval
        return urlRequest
    }
    
}
