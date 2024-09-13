//
//  AuthService.swift
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

public protocol AuthService {

}

public struct DefaultAuthService: AuthService {

    let baseURL: URL
    var apiService: APIService
    let sessionDelegate = SessionDelegate()
    let urlSessionOperationQueue = OperationQueue()

    /// Default initialiser
    /// - Parameters:
    ///   - baseURL: The API protocol + host url, used for building all API requests' URL
    public init(baseURL: URL) {
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.default
        let urlSession = URLSession(configuration: configuration,
                                    delegate: sessionDelegate,
                                    delegateQueue: urlSessionOperationQueue)
        self.apiService = DefaultAPIService(urlSession: urlSession)
    }

    /// Initialiser for TESTING purposes only
    /// - Parameters:
    ///   - baseURL: The API base url, used for building all requests URL
    ///   - apiService: A custom apiService. Warning: Auth API answers with redirects that should be ignored, the custom URLSession with SessionDelegate as delegate handles this scenario correctly, a custom one would not.
    internal init(baseURL: URL, apiService: APIService) {
        self.baseURL = baseURL
        self.apiService = apiService
    }

    /// Extract an header from the HTTP response
    /// - Parameters:
    ///   - header: The header key
    ///   - httpResponse: The HTTP URL Response
    /// - Returns: The header value, throws an error if not present
    func extract(header: String, from httpResponse: HTTPURLResponse) throws -> String {
        let headers = httpResponse.allHeaderFields
        guard let result = headers[header] as? String else {
            throw AuthServiceError.missingResponseValue(header)
        }
        return result
    }

    /// Extract an API error from the HTTP response body.
    ///  The Auth API can answer with errors in the HTTP response body, format: `{ "error": "$error_code" }`, this function decodes the body in `AuthRequest.BodyError`and generates an AuthServiceError containing the error info
    /// - Parameter responseBody: The HTTP response body Data
    /// - Returns: and AuthServiceError.authAPIError containing the error code and description, nil if the body
    func extractError(from responseBody: Data, request: AuthRequest) -> AuthServiceError? {
        let decoder = JSONDecoder()
        guard let bodyError = try? decoder.decode(AuthRequest.BodyError.self, from: responseBody) else {
            return nil
        }
        let description = request.errorDetails[bodyError.error] ?? "Missing description"
        return AuthServiceError.authAPIError(code: bodyError.error, description: description)
    }

    func throwError(forErrorBody body: Data?, request: AuthRequest) throws {
        if let body,
           let error = extractError(from: body, request: request) {
            throw error
        } else {
            throw AuthServiceError.missingResponseValue("Body error")
        }
    }

    // MARK: - API requests

    // MARK: Authorise

    public struct AuthoriseResponse {
        let location: String
        let setCookie: String
    }

    public func authorise(codeChallenge: String) async throws -> AuthoriseResponse {

        guard let request = AuthRequest.authorize(baseURL: baseURL, codeChallenge: codeChallenge) else {
            throw AuthServiceError.invalidRequest
        }

        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            let location = try extract(header: HTTPHeaderKey.location, from: response.httpResponse)
            let setCookie = try extract(header: HTTPHeaderKey.setCookie, from: response.httpResponse)
            Logger.networking.debug("\(#function) request completed")
            return AuthoriseResponse(location: location, setCookie: setCookie)
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forErrorBody: response.data, request: request)
        }
        throw AuthServiceError.invalidResponseCode(statusCode)
    }

    // MARK: Create Account

    public struct CreateAccountResponse {
        let location: String
    }

    public func createAccount(authSessionID: String) async throws -> CreateAccountResponse {
        guard let request = AuthRequest.createAccount(baseURL: baseURL, authSessionID: authSessionID) else {
            throw AuthServiceError.invalidRequest
        }

        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            let location = try extract(header: HTTPHeaderKey.location, from: response.httpResponse)
            Logger.networking.debug("\(#function) request completed")
            return CreateAccountResponse(location: location)
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forErrorBody: response.data, request: request)
        }
        throw AuthServiceError.invalidResponseCode(statusCode)
    }

    // MARK: Send OTP

    public func sendOTP(authSessionID: String, emailAddress: String) async throws {
        guard let request = AuthRequest.sendOTP(baseURL: baseURL, authSessionID: authSessionID, emailAddress: emailAddress) else {
            throw AuthServiceError.invalidRequest
        }

        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            Logger.networking.debug("\(#function) request completed")
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forErrorBody: response.data, request: request)
        }
        throw AuthServiceError.invalidResponseCode(statusCode)
    }
}
