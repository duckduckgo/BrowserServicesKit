//
//  AuthServiceError.swift
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

enum AuthServiceError: Error, LocalizedError {
    case authAPIError(code: String, description: String)
    case apiServiceError(Error)
    case invalidRequest
    case invalidResponseCode(HTTPStatusCode)
    case missingResponseValue(String)

    public var errorDescription: String? {
        switch self {
        case .authAPIError(let code, let description):
            "Auth API responded with error \(code) - \(description)"
        case .apiServiceError(let error):
            "API service error - \(error.localizedDescription)"
        case .invalidRequest:
            "Failed to generate the API request"
        case .invalidResponseCode(let code):
            "Invalid API request response code: \(code.rawValue) - \(code.description)"
        case .missingResponseValue(let value):
            "The API response is missing \(value)"
        }
    }
}
