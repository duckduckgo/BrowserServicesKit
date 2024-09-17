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
import os.log

/// Auth API v2 Endpoints, doc: https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#auth-api-v2-endpoints
struct OAuthRequest {

    let apiRequest: APIRequestV2
    let httpSuccessCode: HTTPStatusCode
    let httpErrorCodes: [HTTPStatusCode]
    let errorDetails: [String: String]

    struct BodyError: Decodable {
        let error: String
    }

    internal init(apiRequest: APIRequestV2,
                  httpSuccessCode: HTTPStatusCode = HTTPStatusCode.ok,
                  httpErrorCodes: [HTTPStatusCode] = [HTTPStatusCode.badRequest, HTTPStatusCode.internalServerError],
                  errorDetails: [String : String]) {
        self.apiRequest = apiRequest
        self.httpSuccessCode = httpSuccessCode
        self.httpErrorCodes = httpErrorCodes
        self.errorDetails = errorDetails
    }

    // MARK: Authorize

    static func authorize(baseURL: URL, codeChallenge: String) -> OAuthRequest? {
        let path = "/api/auth/v2/authorize"
        let queryItems = [
            "response_type": "code",
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256",
            "client_id": "f4311287-0121-40e6-8bbd-85c36daf1837",
            "redirect_uri": "com.duckduckgo:/authcb",
            "scope": "privacypro"
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems) else {
            return nil
        }
        let errorDetails = [
            "invalid_authorization_request": "One or more of the required parameters are missing or any provided parameters have invalid values.",
            "authorize_failed": "Failed to create the authorization session, either because of a reused code challenge or internal server error.",
        ]
        return OAuthRequest(apiRequest: request,
                           httpSuccessCode: HTTPStatusCode.found,
                           errorDetails: errorDetails)
    }

    // MARK: Create account

    static func createAccount(baseURL: URL, authSessionID: String) -> OAuthRequest? {
        let path = "/api/auth/v2/account/create"
        let headers = [ HTTPHeaderKey.cookie: authSessionID ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        let errorDetails = [
            "invalid_request": "The ddg_auth_session_id is missing or has already been used to log in to a different account.",
            "account_create_failed": "Failed to create the account because of an internal server error."
        ]
        return OAuthRequest(apiRequest: request,
                           httpSuccessCode: HTTPStatusCode.found,
                           errorDetails: errorDetails)
    }

    // MARK: Sent OTP

    static func sendOTP(baseURL: URL, authSessionID: String, emailAddress: String) -> OAuthRequest? {
        let path = "/api/auth/v2/otp"
        let headers = [ HTTPHeaderKey.cookie: authSessionID ]
        let queryItems = [ "email": emailAddress ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         queryItems: queryItems,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        let errorDetails = [
             "invalid_email_address": "Provided email address is missing or of an invalid format.",
             "invalid_session_id": "The session id is missing, invalid or has already been used for logging in.",
             "suspended_account": "The account you are logging in to is suspended.",
             "email_sending_error": "Failed to send the OTP to the email address provided."
        ]
        return OAuthRequest(apiRequest: request,
                           errorDetails: errorDetails)
    }

    // MARK: Login

    static func login(baseURL: URL, authSessionID: String, method: OAuthLoginMethod) -> OAuthRequest? {
        let path = "/api/auth/v2/login"
        let headers = [ HTTPHeaderKey.cookie: authSessionID ]
        var queryItems: [String: String]
        switch method.self {
        case is OAuthLoginMethodOTP:
            guard let otpMethod = method as? OAuthLoginMethodOTP else {
                return nil
            }
            queryItems = [
                "method": otpMethod.name,
                "email": otpMethod.email,
                "otp": otpMethod.otp
            ]
        case is OAuthLoginMethodSignature:
            guard let signatureMethod = method as? OAuthLoginMethodSignature else {
                return nil
            }
            queryItems = [
                "method": signatureMethod.name,
                "email": signatureMethod.signature,
                "source": signatureMethod.source
            ]
        default:
            Logger.networking.fault("Unknown login method: \(String(describing: method))")
            return nil
        }

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         queryItems: queryItems,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        let errorDetails = [
            "invalid_login_credentials": "One or more of the provided parameters is invalid.",
            "invalid_session_id": "The session id is missing, invalid or has already been used for logging in.",
            "suspended_account": "The account you are logging in to is suspended.",
            "unknown_account": "The login credentials appear valid but do not link to a known account."
        ]
        return OAuthRequest(apiRequest: request,
                           httpSuccessCode: HTTPStatusCode.found,
                           errorDetails: errorDetails)
    }

    // MARK: Access Token
    // Note: The API has a single endpoint for both getting a new token and refreshing an old one, but here I'll split the endpoint in 2 different calls
    // https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#access-token

    static let accessTokenErrorDetails = [
         "invalid_token_request": "One or more of the required parameters are missing or any provided parameters have invalid values.",
         "suspended_account": "The account you are logging in to is suspended.",
         "unknown_account": "The login credentials appear valid but do not link to a known account."
    ]

    static func getAccessToken(baseURL: URL, clientID: String, codeVerifier: String, code: String, redirectURI: String) -> OAuthRequest? {
        let path = "/api/auth/v2/token"
        let queryItems = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code_verifier": codeVerifier,
            "code": code,
            "redirect_uri": redirectURI
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems) else {
            return nil
        }

        return OAuthRequest(apiRequest: request,
                           httpSuccessCode: .ok,
                           errorDetails: accessTokenErrorDetails)
    }

    static func refreshAccessToken(baseURL: URL, clientID: String, refreshToken: String) -> OAuthRequest? {
        let path = "/api/auth/v2/token"
        let queryItems = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems) else {
            return nil
        }
        return OAuthRequest(apiRequest: request,
                           httpSuccessCode: .ok,
                           errorDetails: accessTokenErrorDetails)
    }

    // MARK:


}
