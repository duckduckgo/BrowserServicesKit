//
//  APIService.swift
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
import os.log

public enum APIServiceError: Swift.Error {
    case decodingError
    case encodingError
    case serverError(statusCode: Int, error: String?)
    case unknownServerError
    case connectionError
}

struct ErrorResponse: Decodable {
    let error: String
}

public protocol APIService {
    func executeAPICall<T>(method: String, endpoint: String, headers: [String: String]?, body: Data?) async -> Result<T, APIServiceError> where T: Decodable
    func makeAuthorizationHeader(for token: String) -> [String: String]
}

public enum APICachePolicy {
    case reloadIgnoringLocalCacheData
    case returnCacheDataElseLoad
    case returnCacheDataDontLoad
}

public struct DefaultAPIService: APIService {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession) {
        self.baseURL = baseURL
        self.session = session
    }

    public func executeAPICall<T>(method: String, endpoint: String, headers: [String: String]? = nil, body: Data? = nil) async -> Result<T, APIServiceError> where T: Decodable {
        let request = makeAPIRequest(method: method, endpoint: endpoint, headers: headers, body: body)

        do {
            let (data, urlResponse) = try await session.data(for: request)

            printDebugInfo(method: method, endpoint: endpoint, data: data, response: urlResponse)

            guard let httpResponse = urlResponse as? HTTPURLResponse else { return .failure(.unknownServerError) }

            if (200..<300).contains(httpResponse.statusCode) {
                if let decodedResponse = decode(T.self, from: data) {
                    return .success(decodedResponse)
                } else {
                    Logger.subscription.error("Service error: APIServiceError.decodingError")
                    return .failure(.decodingError)
                }
            } else {
                var errorString: String?

                if let decodedResponse = decode(ErrorResponse.self, from: data) {
                    errorString = decodedResponse.error
                }

                let errorLogMessage = "/\(endpoint) \(httpResponse.statusCode): \(errorString ?? "")"
                Logger.subscription.error("Service error: \(errorLogMessage, privacy: .public)")
                return .failure(.serverError(statusCode: httpResponse.statusCode, error: errorString))
            }
        } catch {
            Logger.subscription.error("Service error: \(error.localizedDescription, privacy: .public)")
            return .failure(.connectionError)
        }
    }

    private func makeAPIRequest(method: String, endpoint: String, headers: [String: String]?, body: Data?) -> URLRequest {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let headers = headers {
            request.allHTTPHeaderFields = headers
        }
        if let body = body {
            request.httpBody = body
        }

        return request
    }

    private func decode<T>(_: T.Type, from data: Data) -> T? where T: Decodable {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return try? decoder.decode(T.self, from: data)
    }

    private func printDebugInfo(method: String, endpoint: String, data: Data, response: URLResponse) {
        let statusCode = (response as? HTTPURLResponse)!.statusCode
        let stringData = String(data: data, encoding: .utf8) ?? ""

        Logger.subscription.info("[API] \(statusCode) \(method, privacy: .public) \(endpoint, privacy: .public) :: \(stringData, privacy: .public)")
    }

    public func makeAuthorizationHeader(for token: String) -> [String: String] {
        ["Authorization": "Bearer " + token]
    }
}

fileprivate extension URLResponse {

    var httpStatusCodeAsString: String? {
        guard let httpStatusCode = (self as? HTTPURLResponse)?.statusCode else { return nil }
        return String(httpStatusCode)
    }
}
