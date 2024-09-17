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

    func fetch<T: Decodable>(request: APIRequestV2) async throws -> (responseBody: T?, httpResponse: HTTPURLResponse)
//    func fetch<T: Decodable>(request: APIRequestV2) async throws -> T?
    func fetch(request: APIRequestV2) async throws -> APIService.APIResponse
}

public struct DefaultAPIService: APIService {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession

    }

    public func fetch<T: Decodable>(request: APIRequestV2) async throws -> (responseBody: T?, httpResponse: HTTPURLResponse)  {
        try Task.checkCancellation()
        let response: APIService.APIResponse = try await fetch(request: request)

        guard let data = response.data else {
            return (nil, response.httpResponse)
        }

        try Task.checkCancellation()

        // Try to decode the data
        Logger.networking.debug("Decoding response body as \(T.self)")
        switch T.self {
        case is String.Type:
            guard let resultString = String(data: data, encoding: .utf8) as? T else {
                let error = APIRequestV2.Error.invalidDataType
                Logger.networking.error("Error: \(error.localizedDescription)")
                throw error
            }
            return (resultString, response.httpResponse)
        default:
            // Decode data
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode(T.self, from: data)
            return (decodedData, response.httpResponse)
        }
    }

    /// Fetch an API Request
    /// - Parameter request: A configured APIRequest
    /// - Returns: An instance of the inferred decodable object, can be a `String` or any `Decodable` model, nil if the response body is empty
//    public func fetch<T: Decodable>(request: APIRequestV2) async throws -> T? {
//        let response: APIService.APIResponse = try await fetch(request: request)
//
//        guard let data = response.data else {
//            return nil
//        }
//
//        try Task.checkCancellation()
//
//        // Try to decode the data
//        Logger.networking.debug("Decoding response body as \(T.self)")
//        switch T.self {
//        case is String.Type:
//            guard let resultString = String(data: data, encoding: .utf8) as? T else {
//                let error = APIRequestV2.Error.invalidDataType
//                Logger.networking.error("Error: \(error.localizedDescription)")
//                throw error
//            }
//            return resultString
//        default:
//            // Decode data
//            let decoder = JSONDecoder()
//            return try decoder.decode(T.self, from: data)
//        }
//    }

    /// Fetch an API Request
    /// - Parameter request: A configured APIRequest
    /// - Returns: An `APIResponse`, a tuple composed by `(data: Data?, httpResponse: HTTPURLResponse)`
    public func fetch(request: APIRequestV2) async throws -> APIService.APIResponse {

        Logger.networking.debug("Fetching: \(request.debugDescription)")
        let (data, response) = try await fetch(for: request.urlRequest)
        Logger.networking.debug("Response: \(response.debugDescription) Data size: \(data.count) bytes")

        try Task.checkCancellation()

        // Check response code
        let httpResponse = try response.asHTTPURLResponse()
        let responseHTTPStatus = httpResponse.httpStatus
        if responseHTTPStatus.isFailure {
            return (data, httpResponse)
        }

        // Check requirements
        let notModifiedIsAllowed: Bool = request.responseConstraints?.contains(.allowHTTPNotModified) ?? false
        if responseHTTPStatus == .notModified && !notModifiedIsAllowed {
            let error = APIRequestV2.Error.unsatisfiedRequirement(.allowHTTPNotModified)
            Logger.networking.error("Error: \(error.localizedDescription)")
            throw error
        }
        if let requirements = request.responseConstraints {
            for requirement in requirements {
                switch requirement {
                case .requireETagHeader:
                    guard httpResponse.etag != nil else {
                        let error = APIRequestV2.Error.unsatisfiedRequirement(requirement)
                        Logger.networking.error("Error: \(error.localizedDescription)")
                        throw error
                    }
                case .requireUserAgent:
                    guard let userAgent = httpResponse.allHeaderFields[HTTPHeaderKey.userAgent] as? String,
                          userAgent.isEmpty == false else {
                        let error = APIRequestV2.Error.unsatisfiedRequirement(requirement)
                        Logger.networking.error("Error: \(error.localizedDescription)")
                        throw error
                    }
                default: break
                }
            }
        }

        return (data, httpResponse)
    }

    /// Fetch data using the class URL session, in case of error wraps it in a `APIRequestV2.Error.urlSession` error
    /// - Parameter request: The URLRequest to fetch
    /// - Returns: The Data fetched and the URLResponse
    internal func fetch(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error {
            throw APIRequestV2.Error.urlSession(error)
        }
    }
}
