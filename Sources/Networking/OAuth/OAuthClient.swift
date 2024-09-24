//
//  OAuthClient.swift
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

public enum OAuthClientError: Error, LocalizedError {
    case internalError(String)
    case missingRefreshToken
    case unauthenticated

    public var errorDescription: String? {
        switch self {
        case .internalError(let error):
            return "Internal error: \(error)"
        case .missingRefreshToken:
            return "No refresh token available, please re-authenticate"
        case .unauthenticated:
            return "The account is not authenticated, please re-authenticate"
        }
    }
}

final public class OAuthClient {

    public protocol TokensStoring {
        var accessToken: String? { get set }
        var decodedAccessToken: OAuthAccessToken? { get set }
        var refreshToken: String? { get set }
        var decodedRefreshToken: OAuthRefreshToken? { get set }
    }

    public struct Constants {
        /// https://app.asana.com/0/1205784033024509/1207979495854201/f
        static let clientID = "f4311287-0121-40e6-8bbd-85c36daf1837"
        static let redirectURI = "com.duckduckgo:/authcb"
        static let availableScopes = [ "privacypro" ]

        public static let productionBaseURL = URL(string: "https://quack.duckduckgo.com")!
        public static let stagingBaseURL = URL(string: "https://quackdev.duckduckgo.com")!
    }

    // MARK: -

    let authService: OAuthService
    var tokensStorage: TokensStoring

    public init(authService: OAuthService = DefaultOAuthService(baseURL: Constants.stagingBaseURL), // TODO: change to production
         tokensStorage: any TokensStoring) {
        self.authService = authService
        self.tokensStorage = tokensStorage
    }

    // MARK: - Internal

    internal func getTokens(authCode: String, codeVerifier: String) async throws {
        let getTokensResponse = try await authService.getAccessToken(clientID: Constants.clientID,
                                                             codeVerifier: codeVerifier,
                                                             code: authCode,
                                                             redirectURI: Constants.redirectURI)
        let jwtSigners = try await authService.getJWTSigners()
        let decodedAccessToken = try jwtSigners.verify(getTokensResponse.accessToken, as: OAuthAccessToken.self)
        let decodedRefreshToken = try jwtSigners.verify(getTokensResponse.refreshToken, as: OAuthRefreshToken.self)
        tokensStorage.accessToken = getTokensResponse.accessToken
        tokensStorage.decodedAccessToken = decodedAccessToken
        tokensStorage.refreshToken = getTokensResponse.refreshToken
        tokensStorage.decodedRefreshToken = decodedRefreshToken
    }

//    internal func createAccountIfNeeded() async throws {
//        if tokensStorage.accessToken == nil {
//            try await createAccount()
//        }
//    }

    func getVerificationCodes() async throws -> (codeVerifier: String, codeChallenge: String) {
        let codeVerifier = OAuthCodesGenerator.codeVerifier
        guard let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: codeVerifier) else {
            throw OAuthClientError.internalError("Failed to generate code challenge")
        }
        return (codeVerifier, codeChallenge)
    }

    // MARK: - Public

    public func getValidAccessToken() async throws -> String {
        if let token = tokensStorage.accessToken {
            if tokensStorage.decodedAccessToken?.isExpired() == false {
                return token
            } else {
                try await refreshToken()
                if let token = tokensStorage.accessToken {
                    return token
                }
            }
        }
        throw OAuthClientError.unauthenticated
    }

    // MARK: Create

    public func createAccount() async throws {
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        let authCode = try await authService.createAccount(authSessionID: authSessionID)
        try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
    }

    // MARK: Activate

    /// Helper, single use // TODO: doc
    public class EmailAccountActivator {

        private let oAuthClient: OAuthClient
        private var email: String? = nil
        private var authSessionID: String? = nil
        private var codeVerifier: String? = nil

        internal init(oAuthClient: OAuthClient) {
            self.oAuthClient = oAuthClient
        }

        func activateWith(email: String) async throws {
            self.email = email
            let (authSessionID, codeVerifier) = try await oAuthClient.requestOTP(email: email)
            self.authSessionID = authSessionID
            self.codeVerifier = codeVerifier
        }

        func confirm(otp: String) async throws {
            guard let codeVerifier, let authSessionID, let email else { return }
            try await oAuthClient.activate(withOTP: otp, email: email, codeVerifier: codeVerifier, authSessionID: authSessionID)
        }
    }

    public func requestOTP(email: String) async throws -> (authSessionID: String, codeVerifier: String) {
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        try await authService.requestOTP(authSessionID: authSessionID, emailAddress: email)
        return (authSessionID, codeVerifier) // to be used in activate(withOTP or activate(withPlatformSignature
    }

    public func activate(withOTP otp: String, email: String, codeVerifier: String, authSessionID: String) async throws {
        let authCode = try await authService.login(withOTP: otp, authSessionID: authSessionID, email: email)
        try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
    }

    public func activate(withPlatformSignature signature: String, codeVerifier: String, authSessionID: String) async throws {
        let authCode = try await authService.login(withSignature: signature, authSessionID: authSessionID)
        try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
    }

    // MARK: Refresh

    public func refreshToken() async throws {
        guard let refreshToken = tokensStorage.refreshToken else {
            throw OAuthClientError.missingRefreshToken
        }
        let refreshTokenResponse = try await authService.refreshAccessToken(clientID: Constants.clientID, refreshToken: refreshToken)
        let jwtSigners = try await authService.getJWTSigners()
        let decodedAccessToken = try jwtSigners.verify(refreshTokenResponse.accessToken, as: OAuthAccessToken.self)
        let decodedRefreshToken = try jwtSigners.verify(refreshTokenResponse.refreshToken, as: OAuthRefreshToken.self)
        tokensStorage.accessToken = refreshTokenResponse.accessToken
        tokensStorage.decodedAccessToken = decodedAccessToken
        tokensStorage.refreshToken = refreshTokenResponse.refreshToken
        tokensStorage.decodedRefreshToken = decodedRefreshToken
    }

    // MARK: Exchange V1 to V2 token

    public func exchange(accessTokenV1: String) async throws {
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        let refreshTokenResponse = try await authService.exchangeToken(accessTokenV1: accessTokenV1, authSessionID: authSessionID)
    }

    // MARK: Logout

    public func logout() async throws {
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        guard let token = tokensStorage.accessToken else {
            throw OAuthClientError.unauthenticated
        }
        try await authService.logout(accessToken: token)
    }

    // MARK: Edit account

    /// Helper, single use // TODO: doc
    public class AccountEditor {

        private let oAuthClient: OAuthClient
        private var hashString: String? = nil
        private var email: String? = nil

        internal init(oAuthClient: OAuthClient) {
            self.oAuthClient = oAuthClient
        }

        public func change(email: String?) async throws {
            self.hashString = try await self.oAuthClient.changeAccount(email: email)
        }

        public func send(otp: String) async throws {
            guard let email, let hashString else {
                throw OAuthClientError.internalError("Missing email or hashString")
            }
            try await oAuthClient.confirmChangeAccount(email: email, otp: otp, hash: hashString)
        }
    }

    public func changeAccount(email: String?) async throws -> String {
        guard let token = tokensStorage.accessToken else {
            throw OAuthClientError.unauthenticated
        }
        let editAccountResponse = try await authService.editAccount(clientID: Constants.clientID, accessToken: token, email: email)
        return editAccountResponse.hash
    }

    public func confirmChangeAccount(email: String, otp: String, hash: String) async throws {
        guard let token = tokensStorage.accessToken else {
            throw OAuthClientError.unauthenticated
        }
        let response = try await authService.confirmEditAccount(accessToken: token, email: email, hash: hash, otp: otp)
    }
}
