//
//  APIService.swift
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
import os.log

public protocol APIService {

    typealias APIResponse = (data: Data?, httpResponse: HTTPURLResponse)

    func fetch<T: Decodable>(request: APIRequestV2) async throws -> T
    func fetch(request: APIRequestV2) async throws -> APIService.APIResponse
}

public struct DefaultAPIService: APIService {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Fetch an API Request
    /// - Parameter request: A configured APIRequest
    /// - Returns: An instance of the inferred decodable object, can be a String or a Decodable model
    public func fetch<T: Decodable>(request: APIRequestV2) async throws -> T {
        let response: APIService.APIResponse = try await fetch(request: request)

        guard let data = response.data else {
            throw APIRequestV2.Error.emptyData
        }

        try Task.checkCancellation()

        // Try to decode the data
        switch T.self {
        case is String.Type:
            guard let resultString = String(data: data, encoding: .utf8) as? T else {
                throw APIRequestV2.Error.invalidDataType
            }
            return resultString
        default:
            // Decode data
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        }
    }

    /// Fetch an API Request
    /// - Parameter request: A configured API request
    /// - Returns: An `APIResponse`, a tuple composed by (data: Data?, httpResponse: HTTPURLResponse)
    public func fetch(request: APIRequestV2) async throws -> APIService.APIResponse {

        try Task.checkCancellation()

        Logger.networking.debug("Fetching: \(request.debugDescription)")
        let (data, response) = try await fetch(for: request.urlRequest)
        Logger.networking.debug("Response: \(response.debugDescription) Data size: \(data.count) bytes")
        let httpResponse = try response.asHTTPURLResponse()
        let responseHTTPStatus = httpResponse.httpStatus

        try Task.checkCancellation()

        // Check response code
        if responseHTTPStatus.isFailure {
            throw APIRequestV2.Error.invalidStatusCode(httpResponse.statusCode)
        }

        // Check requirements
        if responseHTTPStatus == .notModified && !request.requirements.contains(.allowHTTPNotModified) {
            throw APIRequestV2.Error.unsatisfiedRequirement(.allowHTTPNotModified)
        }
        for requirement in request.requirements {
            switch requirement {
            case .requireETagHeader:
                guard httpResponse.etag != nil else {
                    throw APIRequestV2.Error.unsatisfiedRequirement(requirement)
                }
            case .requireUserAgent:
                guard let userAgent = httpResponse.allHeaderFields[HTTPHeaderKey.userAgent] as? String,
                        !userAgent.isEmpty else {
                    throw APIRequestV2.Error.unsatisfiedRequirement(requirement)
                }
            case .allowHTTPNotModified:
                break
            }
        }

        return (data, httpResponse)
    }

    /// Fetch data using the class URL session, in case of error wraps it in a `APIRequestV2.Error.urlSession` error
    /// - Parameter request: The URLRequest to fetch
    /// - Returns: The Data fetched and the URLResponse
    func fetch(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error {
            throw APIRequestV2.Error.urlSession(error)
        }
    }
}
