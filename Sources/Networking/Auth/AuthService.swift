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

public struct AuthService {

    let baseURL: URL
    let apiService: APIService

    func extract(header: String, from httpResponse: HTTPURLResponse) throws -> String {
        let headers = httpResponse.allHeaderFields
        guard let result = headers[header] as? String else {
            throw AuthServiceError.missingResponseValue(header)
        }
        return result
    }

    func extractError(from)

    // MARK: Auth API Requests

    public func authorise(codeChallenge: String) async throws {

        guard let authRequest = AuthRequest.authorize(baseURL: baseURL, codeChallenge: codeChallenge) else {
            throw AuthServiceError.invalidRequest
        }
        let response = try await apiService.fetch(request: authRequest.apiRequest)
        let statusCode = response.httpResponse.httpStatus
        if statusCode == authRequest.httpSuccessCode {
            let headers = response.httpResponse.allHeaderFields
            let location = try extract(header: HTTPHeaderKey.location, from: response.httpResponse)
            let setCookie = try extract(header: HTTPHeaderKey.setCookie, from: response.httpResponse)

        } else if authRequest.httpErrorCodes.contains(statusCode) {

        } else {
            throw AuthServiceError.invalidResponseCode(statusCode)
        }
    }
}
