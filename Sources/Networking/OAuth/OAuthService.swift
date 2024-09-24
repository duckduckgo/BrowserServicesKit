//
//  OAuthService.swift
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
import JWTKit

public protocol OAuthService {

    /// Authorizes a user with a given code challenge.
    /// - Parameter codeChallenge: The code challenge for authorization.
    /// - Returns: An OAuthSessionID.
    /// - Throws: An error if the authorization fails.
    func authorise(codeChallenge: String) async throws -> OAuthSessionID

    /// Creates a new account using the provided auth session ID.
    /// - Parameter authSessionID: The authentication session ID.
    /// - Returns: The authorization code needed for the Access Token request.
    /// - Throws: An error if account creation fails.
    func createAccount(authSessionID: String) async throws -> AuthorisationCode

    /// Sends an OTP to the specified email address.
    /// - Parameters:
    ///   - authSessionID: The authentication session ID.
    ///   - emailAddress: The email address to send the OTP to.
    /// - Throws: An error if sending the OTP fails.
    func requestOTP(authSessionID: String, emailAddress: String) async throws

    /// Logs in a user with an OTP and auth session ID.
    /// - Parameters:
    ///   - otp: The One Time Password received from the user
    ///   - authSessionID: The authentication session ID.
    ///   - email: the user email where the otp will be received
    /// - Returns: An OAuthRedirectionURI.
    /// - Throws: An error if login fails.
    func login(withOTP otp: String, authSessionID: String, email: String) async throws -> AuthorisationCode

    /// Logs in a user with a signature and auth session ID.
    /// - Parameters:
    ///   - signature: The platform signature
    ///   - authSessionID: The authentication session ID.
    /// - Returns: An OAuthRedirectionURI.
    /// - Throws: An error if login fails.
    func login(withSignature signature: String, authSessionID: String) async throws -> AuthorisationCode

    /// Retrieves an access token using the provided parameters.
    /// - Parameters:
    ///   - clientID: The client ID.
    ///   - codeVerifier: The code verifier.
    ///   - code: The authorization code.
    ///   - redirectURI: The redirect URI.
    /// - Returns: An OAuthTokenResponse.
    /// - Throws: An error if token retrieval fails.
    func getAccessToken(clientID: String, codeVerifier: String, code: String, redirectURI: String) async throws -> OAuthTokenResponse

    /// Refreshes an access token using the provided client ID and refresh token.
    /// - Parameters:
    ///   - clientID: The client ID.
    ///   - refreshToken: The refresh token.
    /// - Returns: An OAuthTokenResponse.
    /// - Throws: An error if token refresh fails.
    func refreshAccessToken(clientID: String, refreshToken: String) async throws -> OAuthTokenResponse

    /// Edits the account email address.
    /// - Parameters:
    ///   - clientID: The client ID.
    ///   - accessToken: The access token.
    ///   - email: The new email address, or nil to remove the email.
    /// - Returns: An EditAccountResponse.
    /// - Throws: An error if the edit fails.
    func editAccount(clientID: String, accessToken: String, email: String?) async throws -> EditAccountResponse

    /// Confirms the edit of an account email address.
    /// - Parameters:
    ///   - accessToken: The access token.
    ///   - email: The new email address.
    ///   - hash: The hash used for confirmation.
    ///   - otp: The one-time password.
    /// - Returns: A ConfirmEditAccountResponse.
    /// - Throws: An error if confirmation fails.
    func confirmEditAccount(accessToken: String, email: String, hash: String, otp: String) async throws -> ConfirmEditAccountResponse

    /// Logs out the user using the provided access token.
    /// - Parameter accessToken: The access token.
    /// - Throws: An error if logout fails.
    func logout(accessToken: String) async throws

    /// Exchanges an access token for a new one.
    /// - Parameters:
    ///   - accessTokenV1: The old access token.
    ///   - authSessionID: The authentication session ID.
    /// - Returns: An OAuthRedirectionURI.
    /// - Throws: An error if the exchange fails.
    func exchangeToken(accessTokenV1: String, authSessionID: String) async throws -> AuthorisationCode

    /// Retrieves JWT signers using JWKs from the endpoint.
    /// - Returns: A JWTSigners instance.
    /// - Throws: An error if retrieval fails.
    func getJWTSigners() async throws -> JWTSigners
}

public struct DefaultOAuthService: OAuthService {

    private let baseURL: URL
    private var apiService: APIService
    private let sessionDelegate = SessionDelegate()
    private let urlSessionOperationQueue = OperationQueue()
    /// Not really used but implemented as a way to isolate the possible cookies received by the OAuth API calls.
    private let localCookieStorage = HTTPCookieStorage()

    /// Default initialiser
    /// - Parameters:
    ///   - baseURL: The API protocol + host url, used for building all API requests' URL
    public init(baseURL: URL) {
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = localCookieStorage
        let urlSession = URLSession(configuration: configuration,
                                    delegate: sessionDelegate,
                                    delegateQueue: urlSessionOperationQueue)
        self.apiService = DefaultAPIService(urlSession: urlSession)
    }

    /// Initialiser for TESTING purposes only
    /// - Parameters:
    ///   - baseURL: The API base url, used for building all requests URL
    ///   - apiService: A custom apiService. Warning: Some AuthAPI endpoints response is a redirect that is handled in a very specific way. The default apiService uses a URLSession that handles this scenario correctly implementing a SessionDelegate, a custom one would brake this.
    internal init(baseURL: URL, apiService: APIService) {
        self.baseURL = baseURL
        self.apiService = apiService
    }

    /// Extract an header from the HTTP response
    /// - Parameters:
    ///   - header: The header key
    ///   - httpResponse: The HTTP URL Response
    /// - Returns: The header value, throws an error if not present
    internal func extract(header: String, from httpResponse: HTTPURLResponse) throws -> String {
        let headers = httpResponse.allHeaderFields
        guard let result = headers[header] as? String else {
            throw OAuthServiceError.missingResponseValue(header)
        }
        return result
    }

    /// Extract an API error from the HTTP response body.
    ///  The Auth API can answer with errors in the HTTP response body, format: `{ "error": "$error_code" }`, this function decodes the body in `AuthRequest.BodyError`and generates an AuthServiceError containing the error info
    /// - Parameter responseBody: The HTTP response body Data
    /// - Returns: and AuthServiceError.authAPIError containing the error code and description, nil if the body
    internal func extractError(from response: APIResponseV2, request: OAuthRequest) -> OAuthServiceError? {
        if let bodyError: OAuthRequest.BodyError = try? response.decodeBody() {
            let description = OAuthRequest.errorDetails[bodyError.error] ?? "Missing description"
            return OAuthServiceError.authAPIError(code: bodyError.error, description: description)
        }
        return nil
    }

    internal func throwError(forResponse response: APIResponseV2, request: OAuthRequest) throws {
        if let error = extractError(from: response, request: request) {
            throw error
        } else {
            throw OAuthServiceError.missingResponseValue("Body error")
        }
    }

    internal func fetch<T: Decodable>(request: OAuthRequest) async throws -> T {
        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            Logger.OAuth.debug("\(#function) request completed")
            return try response.decodeBody()
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forResponse: response, request: request)
        }
        throw OAuthServiceError.invalidResponseCode(statusCode)
    }

    // MARK: - API requests

    // MARK: Authorise

    public func authorise(codeChallenge: String) async throws -> OAuthSessionID {

        guard let request = OAuthRequest.authorize(baseURL: baseURL, codeChallenge: codeChallenge) else {
            throw OAuthServiceError.invalidRequest
        }

        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            // let location = try extract(header: HTTPHeaderKey.location, from: response.httpResponse)
            guard let cookieValue = response.httpResponse.getCookie(withName: "ddg_auth_session_id")?.value else {
                throw OAuthServiceError.missingResponseValue("ddg_auth_session_id cookie")
            }
            Logger.OAuth.debug("\(#function) request completed")
            return cookieValue
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forResponse: response, request: request)
        }
        throw OAuthServiceError.invalidResponseCode(statusCode)
    }

    // MARK: Create Account

    public func createAccount(authSessionID: String) async throws -> AuthorisationCode {
        guard let request = OAuthRequest.createAccount(baseURL: baseURL, authSessionID: authSessionID) else {
            throw OAuthServiceError.invalidRequest
        }

        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            Logger.OAuth.debug("\(#function) request completed")
            //  The redirect URI from the original Authorization request indicated by the ddg_auth_session_id in the provided Cookie header, with the authorization code needed for the Access Token request appended as a query param. The intention is that the client will intercept this redirect and extract the authorization code to make the Access Token request in the background.
            let redirectURI = try extract(header: HTTPHeaderKey.location, from: response.httpResponse)

            // Extract the code from the URL query params, example: com.duckduckgo:/authcb?code=NgNjnlLaqUomt9b5LDbzAtTyeW9cBNhCGtLB3vpcctluSZI51M9tb2ZDIZdijSPTYBr4w8dtVZl85zNSemxozv
            guard let authCode = URLComponents(string: redirectURI)?.queryItems?.first(where: { queryItem in
                queryItem.name == "code"
            })?.value else {
                throw OAuthServiceError.missingResponseValue("Authorization Code in redirect URI")
            }
            return authCode
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forResponse: response, request: request)
        }
        throw OAuthServiceError.invalidResponseCode(statusCode)
    }

    // MARK: Request OTP

    public func requestOTP(authSessionID: String, emailAddress: String) async throws {
        guard let request = OAuthRequest.requestOTP(baseURL: baseURL, authSessionID: authSessionID, emailAddress: emailAddress) else {
            throw OAuthServiceError.invalidRequest
        }

        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            Logger.OAuth.debug("\(#function) request completed")
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forResponse: response, request: request)
        }
        throw OAuthServiceError.invalidResponseCode(statusCode)
    }

    // MARK: Login

    public func login(withOTP otp: String, authSessionID: String, email: String) async throws -> AuthorisationCode {
        let method = OAuthLoginMethodOTP(email: email, otp: otp)
        guard let request = OAuthRequest.login(baseURL: baseURL, authSessionID: authSessionID, method: method) else {
            throw OAuthServiceError.invalidRequest
        }

        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            Logger.OAuth.debug("\(#function) request completed")
            return try extract(header: HTTPHeaderKey.location, from: response.httpResponse)
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forResponse: response, request: request)
        }
        throw OAuthServiceError.invalidResponseCode(statusCode)
    }

    public func login(withSignature signature: String, authSessionID: String) async throws -> AuthorisationCode {
        let method = OAuthLoginMethodSignature(signature: signature)
        guard let request = OAuthRequest.login(baseURL: baseURL, authSessionID: authSessionID, method: method) else {
            throw OAuthServiceError.invalidRequest
        }

        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            Logger.OAuth.debug("\(#function) request completed")
            return try extract(header: HTTPHeaderKey.location, from: response.httpResponse)
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forResponse: response, request: request)
        }
        throw OAuthServiceError.invalidResponseCode(statusCode)
    }

    // MARK: Access token

    public func getAccessToken(clientID: String, codeVerifier: String, code: String, redirectURI: String) async throws -> OAuthTokenResponse {
        guard let request = OAuthRequest.getAccessToken(baseURL: baseURL, clientID: clientID, codeVerifier: codeVerifier, code: code, redirectURI: redirectURI) else {
            throw OAuthServiceError.invalidRequest
        }
        return try await fetch(request: request)
    }

    public func refreshAccessToken(clientID: String, refreshToken: String) async throws -> OAuthTokenResponse {
        guard let request = OAuthRequest.refreshAccessToken(baseURL: baseURL, clientID: clientID, refreshToken: refreshToken) else {
            throw OAuthServiceError.invalidRequest
        }
        return try await fetch(request: request)
    }

    // MARK: Edit account

    /// Edit an account email address
    /// - Parameters:
    ///   - email: The email address to change to. If omitted, the account email address will be removed.
    /// - Returns: EditAccountResponse containing a status, always "confirmed" and an hash used in the `confirm edit account` API call
    public func editAccount(clientID: String, accessToken: String, email: String?) async throws -> EditAccountResponse {
        guard let request = OAuthRequest.editAccount(baseURL: baseURL, accessToken: accessToken, email: email) else {
            throw OAuthServiceError.invalidRequest
        }
        return try await fetch(request: request)
    }

    public func confirmEditAccount(accessToken: String, email: String, hash: String, otp: String) async throws -> ConfirmEditAccountResponse {
        guard let request = OAuthRequest.confirmEditAccount(baseURL: baseURL, accessToken: accessToken, email: email, hash: hash, otp: otp) else {
            throw OAuthServiceError.invalidRequest
        }
        return try await fetch(request: request)
    }

    // MARK: Logout

    public func logout(accessToken: String) async throws {
        guard let request = OAuthRequest.logout(baseURL: baseURL, accessToken: accessToken) else {
            throw OAuthServiceError.invalidRequest
        }
        let response: LogoutResponse = try await fetch(request: request)
        guard response.status == "logged_out" else {
            throw OAuthServiceError.missingResponseValue("LogoutResponse.status")
        }
    }

    // MARK: Access token exchange

    public func exchangeToken(accessTokenV1: String, authSessionID: String) async throws -> AuthorisationCode {
        guard let request = OAuthRequest.exchangeToken(baseURL: baseURL, accessTokenV1: accessTokenV1, authSessionID: authSessionID) else {
            throw OAuthServiceError.invalidRequest
        }

        try Task.checkCancellation()
        let response = try await apiService.fetch(request: request.apiRequest)
        try Task.checkCancellation()

        let statusCode = response.httpResponse.httpStatus
        if statusCode == request.httpSuccessCode {
            Logger.OAuth.debug("\(#function) request completed")
            return try extract(header: HTTPHeaderKey.location, from: response.httpResponse)
        } else if request.httpErrorCodes.contains(statusCode) {
            try throwError(forResponse: response, request: request)
        }
        throw OAuthServiceError.invalidResponseCode(statusCode)
    }

    // MARK: JWKs

    /// Create a  JWTSigners with the JWKs provided by the endpoint
    /// - Returns: A JWTSigners that can be used to verify JWTs
    public func getJWTSigners() async throws -> JWTSigners {
        try Task.checkCancellation()
        guard let request = OAuthRequest.jwks(baseURL: baseURL) else {
            throw OAuthServiceError.invalidRequest
        }
        try Task.checkCancellation()
        let response: String = try await fetch(request: request)
        let signers = JWTSigners()
        try signers.use(jwksJSON: response)
        return signers
    }

}

// MARK: - Requests' support models and types

public typealias OAuthSessionID = String

public protocol OAuthLoginMethod {
    var name: String { get }
}

public struct OAuthLoginMethodOTP: OAuthLoginMethod {
    public let name = "otp"
    let email: String
    let otp: String
}

public struct OAuthLoginMethodSignature: OAuthLoginMethod {
    public let name = "signature"
    let signature: String
    let source = "apple_store" // TODO: verify with Thomas
}

/// The redirect URI from the original Authorization request indicated by the ddg_auth_session_id in the provided Cookie header, with the authorization code needed for the Access Token request appended as a query param. The intention is that the client will intercept this redirect and extract the authorization code to make the Access Token request in the background.
public typealias AuthorisationCode = String

/// https://www.rfc-editor.org/rfc/rfc6749#section-4.2.2
public struct OAuthTokenResponse: Decodable {
    /// JWT with encoded account details and entitlements. Can be verified using tokens published on the /api/auth/v2/.well-known/jwks.json endpoint. Used to gain access to Privacy Pro BE service resources (VPN, PIR, ITR). Expires after 4 hours, but can be refreshed with a refresh token.
    let accessToken: String
    /// JWT which can be used to get a new access token after the access token expires. Expires after 30 days. Can only be used once. Re-using a refresh token will invalidate any access tokens already issued from that refresh token.
    let refreshToken: String
    /// **ignored** access token expiry date in seconds. The real expiry date will be decoded from the JWT token itself
    let expiresIn: Double
    /// Fix as `Bearer` https://www.rfc-editor.org/rfc/rfc6749#section-7.1
    let tokenType: String

    enum CodingKeys: CodingKey {
        case accessToken
        case refreshToken
        case expiresIn
        case tokenType

        var stringValue: String {
            switch self {
            case .accessToken: return "access_token"
            case .refreshToken: return "refresh_token"
            case .expiresIn: return "expires_in"
            case .tokenType: return "token_type"
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
        self.expiresIn = try container.decode(Double.self, forKey: .expiresIn)
        self.tokenType = try container.decode(String.self, forKey: .tokenType)
    }
}

public struct EditAccountResponse: Decodable {
    let status: String // Always "confirm"
    let hash: String // Edit hash for edit confirmation
}

public struct ConfirmEditAccountResponse: Decodable {
    let status: String // Always "confirmed"
    let email: String // The new email address
}

public struct LogoutResponse: Decodable {
    let status: String // Always "logged_out"
}
