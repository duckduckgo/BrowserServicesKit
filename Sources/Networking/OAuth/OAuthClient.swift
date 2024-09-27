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

public protocol TokensStoring {
    var tokensContainer: TokensContainer? { get set }
}

final public class OAuthClient {

    private struct Constants {
        /// https://app.asana.com/0/1205784033024509/1207979495854201/f
        static let clientID = "f4311287-0121-40e6-8bbd-85c36daf1837"
        static let redirectURI = "com.duckduckgo:/authcb"
        static let availableScopes = [ "privacypro" ]

        public static let productionBaseURL = URL(string: "https://quack.duckduckgo.com")!
        public static let stagingBaseURL = URL(string: "https://quackdev.duckduckgo.com")!
    }

    // MARK: -

    private let authService: OAuthService
    private var tokensStorage: TokensStoring

    public init(tokensStorage: any TokensStoring, authService: OAuthService? = nil) {

        self.tokensStorage = tokensStorage
        if let authService {
            self.authService = authService
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let urlSession = URLSession(configuration: configuration,
                                        delegate: SessionDelegate(),
                                        delegateQueue: nil)
            let apiService = DefaultAPIService(urlSession: urlSession)
            self.authService = DefaultOAuthService(baseURL: Constants.stagingBaseURL, // TODO: change to production
                                                   apiService: apiService)

            apiService.authorizationRefresherCallback = { request in // TODO: is this updated?
                // safety check
                if tokensStorage.tokensContainer?.decodedAccessToken.isExpired() == false {
                    assertionFailure("Refresh attempted on non expired token")
                }
                Logger.OAuth.debug("Refreshing tokens")
                let tokens = try await self.refreshTokens()
                return tokens.accessToken
            }
        }
    }

    // MARK: - Internal

    @discardableResult
    private func getTokens(authCode: String, codeVerifier: String) async throws -> TokensContainer {
        let getTokensResponse = try await authService.getAccessToken(clientID: Constants.clientID,
                                                             codeVerifier: codeVerifier,
                                                             code: authCode,
                                                             redirectURI: Constants.redirectURI)
        return try await decode(accessToken: getTokensResponse.accessToken, refreshToken: getTokensResponse.refreshToken)
    }

    private func getVerificationCodes() async throws -> (codeVerifier: String, codeChallenge: String) {
        let codeVerifier = OAuthCodesGenerator.codeVerifier
        guard let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: codeVerifier) else {
            throw OAuthClientError.internalError("Failed to generate code challenge")
        }
        return (codeVerifier, codeChallenge)
    }

    private func decode(accessToken: String, refreshToken: String) async throws -> TokensContainer {
        let jwtSigners = try await authService.getJWTSigners()
        let decodedAccessToken = try jwtSigners.verify(accessToken, as: JWTAccessToken.self)
        let decodedRefreshToken = try jwtSigners.verify(refreshToken, as: JWTRefreshToken.self)

        return TokensContainer(accessToken: accessToken,
                               refreshToken: refreshToken,
                               decodedAccessToken: decodedAccessToken,
                               decodedRefreshToken: decodedRefreshToken)
    }

    // MARK: - Public

    /// Returns a valid access token
    /// - If present and not expired, from the storage
    /// - if present but expired refreshes it
    /// - if not present creates a new account
    /// All options store the tokens via the tokensStorage
    public func getValidTokens() async throws -> TokensContainer {

        if let tokensContainer = tokensStorage.tokensContainer {
            if tokensContainer.decodedAccessToken.isExpired() == false {
                return tokensContainer
            } else {
                let refreshedTokens = try await refreshTokens()
                tokensStorage.tokensContainer = refreshedTokens
                return refreshedTokens
            }
        } else {
            // We don't have a token stored, create a new account
            let tokens = try await createAccount()
            // Save tokens
            tokensStorage.tokensContainer = tokens
            return tokens
        }
    }

    // MARK: Create

    /// Create an accounts, stores all tokens and returns them
    public func createAccount() async throws -> TokensContainer {
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        let authCode = try await authService.createAccount(authSessionID: authSessionID)
        let tokens = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        return tokens
    }

    // MARK: Activate

    /// Helper, single use // TODO: doc
    public class EmailAccountActivator {

        private let oAuthClient: OAuthClient
        private var email: String? = nil
        private var authSessionID: String? = nil
        private var codeVerifier: String? = nil

        public init(oAuthClient: OAuthClient) {
            self.oAuthClient = oAuthClient
        }

        public func activateWith(email: String) async throws {
            self.email = email
            let (authSessionID, codeVerifier) = try await oAuthClient.requestOTP(email: email)
            self.authSessionID = authSessionID
            self.codeVerifier = codeVerifier
        }

        public func confirm(otp: String) async throws {
            guard let codeVerifier, let authSessionID, let email else { return }
            try await oAuthClient.activate(withOTP: otp, email: email, codeVerifier: codeVerifier, authSessionID: authSessionID)
        }
    }

    private func requestOTP(email: String) async throws -> (authSessionID: String, codeVerifier: String) {
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        try await authService.requestOTP(authSessionID: authSessionID, emailAddress: email)
        return (authSessionID, codeVerifier) // to be used in activate(withOTP or activate(withPlatformSignature
    }

    private func activate(withOTP otp: String, email: String, codeVerifier: String, authSessionID: String) async throws {
        let authCode = try await authService.login(withOTP: otp, authSessionID: authSessionID, email: email)
        try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
    }

    public func activate(withPlatformSignature signature: String) async throws -> TokensContainer {
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        let authCode = try await authService.login(withSignature: signature, authSessionID: authSessionID)
        let tokens = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        tokensStorage.tokensContainer = tokens
        return tokens
    }

    // MARK: Refresh

    @discardableResult
    public func refreshTokens() async throws -> TokensContainer {
        guard let refreshToken = tokensStorage.tokensContainer?.refreshToken else {
            throw OAuthClientError.missingRefreshToken
        }
        let refreshTokenResponse = try await authService.refreshAccessToken(clientID: Constants.clientID, refreshToken: refreshToken)
        let refreshedTokens = try await decode(accessToken: refreshTokenResponse.accessToken, refreshToken: refreshTokenResponse.refreshToken)
        tokensStorage.tokensContainer = refreshedTokens
        return refreshedTokens
    }

    // MARK: Exchange V1 to V2 token

    public func exchange(accessTokenV1: String) async throws -> TokensContainer {
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        let authCode = try await authService.exchangeToken(accessTokenV1: accessTokenV1, authSessionID: authSessionID)
        let tokens = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        tokensStorage.tokensContainer = tokens
        return tokens
    }

    // MARK: Logout

    public func logout() async throws {
        if let token = tokensStorage.tokensContainer?.accessToken {
            try await authService.logout(accessToken: token)
        }
    }

    // MARK: Edit account

    /// Helper, single use // TODO: doc
    public class AccountEditor {

        private let oAuthClient: OAuthClient
        private var hashString: String? = nil
        private var email: String? = nil

        public init(oAuthClient: OAuthClient) {
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
            try await oAuthClient.refreshTokens()
        }
    }

    private func changeAccount(email: String?) async throws -> String {
        guard let token = tokensStorage.tokensContainer?.accessToken else {
            throw OAuthClientError.unauthenticated
        }
        let editAccountResponse = try await authService.editAccount(clientID: Constants.clientID, accessToken: token, email: email)
        return editAccountResponse.hash
    }

    private func confirmChangeAccount(email: String, otp: String, hash: String) async throws {
        guard let token = tokensStorage.tokensContainer?.accessToken else {
            throw OAuthClientError.unauthenticated
        }
        _ = try await authService.confirmEditAccount(accessToken: token, email: email, hash: hash, otp: otp)
    }
}
