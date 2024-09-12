//
//  AuthServiceRequest.swift
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

/// Auth API v2 Endpoints documentation available at https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#auth-api-v2-endpoints
struct AuthRequest {
    let apiRequest: APIRequestV2
    let httpSuccessCode: HTTPStatusCode
    let httpErrorCodes: [HTTPStatusCode]

    struct ConstantQueryValue {
        static let responseType = "code"
        static let clientID = "f4311287-0121-40e6-8bbd-85c36daf1837"
        static let redirectURI = "com.duckduckgo:/authcb"
        static let scope = "privacypro"
    }

    struct BodyError: Decodable {
        let error: String
        let description: String

        init(error: String) {
            self.error = error
            if let description = BodyError.errorDetails[error] {
                self.description = description
            } else {
                assertionFailure("Unknown error type, investigate")
                self.description = "Unknown description"
            }
        }

        enum CodingKeys: CodingKey {
            case error
        }

        init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<AuthRequest.BodyError.CodingKeys> = try decoder.container(keyedBy: AuthRequest.BodyError.CodingKeys.self)
            self.error = try container.decode(String.self, forKey: AuthRequest.BodyError.CodingKeys.error)
            
            guard let description = BodyError.errorDetails[error] else {
                throw AuthServiceError.missingResponseValue("Error code")
            }
            self.description = description
        }

        static let errorDetails = [
            // Authorise
            "invalid_authorization_request": "One or more of the required parameters are missing or any provided parameters have invalid values.",
            "authorize_failed": "Failed to create the authorization session, either because of a reused code challenge or internal server error."
        ]
    }

    static func authorize(baseURL: URL, codeChallenge: String) -> AuthRequest? {
        let path = "/api/auth/v2/authorize"
        let queryItems: [String: String] = [
            "response_type": ConstantQueryValue.responseType,
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256",
            "client_id": ConstantQueryValue.clientID,
            "redirect_uri": ConstantQueryValue.redirectURI,
            "scope": ConstantQueryValue.scope
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems) else {
            return nil
        }

        return AuthRequest(apiRequest: request,
                           httpSuccessCode: HTTPStatusCode.found,
                           httpErrorCodes: [
                            HTTPStatusCode.badRequest,
                            HTTPStatusCode.internalServerError
                           ])
    }
}







