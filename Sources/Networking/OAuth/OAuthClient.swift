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
    case missingTokens
    case missingRefreshToken
    case unauthenticated
    case deadToken

    public var errorDescription: String? {
        switch self {
        case .internalError(let error):
            return "Internal error: \(error)"
        case .missingTokens:
            return "No token available"
        case .missingRefreshToken:
            return "No refresh token available, please re-authenticate"
        case .unauthenticated:
            return "The account is not authenticated, please re-authenticate"
        case .deadToken:
            return "The token can't be refreshed"
        }
    }
}

/// Provides the locally stored tokens container
public protocol TokenStoring {
    var tokenContainer: TokenContainer? { get set }
}

/// Provides the legacy AuthToken V1
public protocol LegacyTokenStoring {
    var token: String? { get set }
}

public enum TokensCachePolicy {
    /// The locally stored one as it is, valid or not
    case local
    /// The locally stored one refreshed
    case localValid

    /// The locally stored one and force the refresh
    case localForceRefresh

    /// Local refreshed, if doesn't exist create a new one
    case createIfNeeded
}

public protocol OAuthClient {

    // MARK: - Public

    var isUserAuthenticated: Bool { get }

    var currentTokenContainer: TokenContainer? { get }

    /// Returns a tokens container based on the policy
    /// - `.local`: returns what's in the storage, as it is, throws an error if no token is available
    /// - `.localValid`: returns what's in the storage, refreshes it if needed. throws an error if no token is available
    /// - `.createIfNeeded`: Returns a tokens container with unexpired tokens, creates a new account if needed
    /// All options store new or refreshed tokens via the tokensStorage
    func getTokens(policy: TokensCachePolicy) async throws -> TokenContainer

    // MARK: Activate

    /// Activate the account with a platform signature
    /// - Parameter signature: The platform signature
    /// - Returns: A container of tokens
    func activate(withPlatformSignature signature: String) async throws -> TokenContainer

    // MARK: Exchange

    /// Exchange token v1 for tokens v2
    /// - Parameter accessTokenV1: The legacy auth token
    /// - Returns: A TokenContainer with access and refresh tokens
    func exchange(accessTokenV1: String) async throws -> TokenContainer

    // MARK: Logout

    /// Logout by invalidating the current access token
    func logout() async throws

    /// Remove the tokens container stored locally
    func removeLocalAccount()
}

final public class DefaultOAuthClient: OAuthClient {

    private struct Constants {
        /// https://app.asana.com/0/1205784033024509/1207979495854201/f
        static let clientID = "f4311287-0121-40e6-8bbd-85c36daf1837"
        static let redirectURI = "com.duckduckgo:/authcb"
        static let availableScopes = [ "privacypro" ]
    }

    // MARK: -

    private let authService: any OAuthService
    public var tokenStorage: any TokenStoring
    public var legacyTokenStorage: (any LegacyTokenStoring)?

    public init(tokensStorage: any TokenStoring,
                legacyTokenStorage: (any LegacyTokenStoring)? = nil,
                authService: OAuthService) {
        self.tokenStorage = tokensStorage
        self.authService = authService
    }

    // MARK: - Internal

    @discardableResult
    private func getTokens(authCode: String, codeVerifier: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Getting tokens")
        let getTokensResponse = try await authService.getAccessToken(clientID: Constants.clientID,
                                                             codeVerifier: codeVerifier,
                                                             code: authCode,
                                                             redirectURI: Constants.redirectURI)
        return try await decode(accessToken: getTokensResponse.accessToken, refreshToken: getTokensResponse.refreshToken)
    }

    private func getVerificationCodes() async throws -> (codeVerifier: String, codeChallenge: String) {
        Logger.OAuthClient.log("Getting verification codes")
        let codeVerifier = OAuthCodesGenerator.codeVerifier
        guard let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: codeVerifier) else {
            Logger.OAuthClient.error("Failed to get verification codes")
            throw OAuthClientError.internalError("Failed to generate code challenge")
        }
        return (codeVerifier, codeChallenge)
    }

    private func decode(accessToken: String, refreshToken: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Decoding tokens")
        let jwtSigners = try await authService.getJWTSigners()
        let decodedAccessToken = try jwtSigners.verify(accessToken, as: JWTAccessToken.self)
        let decodedRefreshToken = try jwtSigners.verify(refreshToken, as: JWTRefreshToken.self)

        return TokenContainer(accessToken: accessToken,
                               refreshToken: refreshToken,
                               decodedAccessToken: decodedAccessToken,
                               decodedRefreshToken: decodedRefreshToken)
    }

    // MARK: - Public

    public var isUserAuthenticated: Bool {
        tokenStorage.tokenContainer != nil
    }

    public var currentTokenContainer: TokenContainer? {
        tokenStorage.tokenContainer
    }

    /// Returns a tokens container based on the policy
    /// - `.local`: returns what's in the storage, as it is, throws an error if no token is available
    /// - `.localValid`: returns what's in the storage, refreshes it if needed. throws an error if no token is available
    /// - `.createIfNeeded`: Returns a tokens container with unexpired tokens, creates a new account if needed
    /// All options store new or refreshed tokens via the tokensStorage
    public func getTokens(policy: TokensCachePolicy) async throws -> TokenContainer {
        let localTokenContainer: TokenContainer?

        // V1 to V2 tokens migration
        if let migratedTokenContainer = await migrateLegacyTokenIfNeeded() {
            localTokenContainer = migratedTokenContainer
        } else {
            localTokenContainer = tokenStorage.tokenContainer
        }

        switch policy {
        case .local:
            Logger.OAuthClient.log("Getting local tokens")
            if let localTokenContainer {
                Logger.OAuthClient.log("Local tokens found, expiry: \(localTokenContainer.decodedAccessToken.exp.value)")
                return localTokenContainer
            } else {
                throw OAuthClientError.missingTokens
            }
        case .localValid:
            Logger.OAuthClient.log("Getting local tokens and refreshing them if needed")
            if let localTokenContainer {
                Logger.OAuthClient.log("Local tokens found, expiry: \(localTokenContainer.decodedAccessToken.exp.value)")
                if localTokenContainer.decodedAccessToken.isExpired() {
                    Logger.OAuthClient.log("Local access token is expired, refreshing it")
                    let refreshedTokens = try await refreshTokens()
                    return refreshedTokens
                } else {
                    return localTokenContainer
                }
            } else {
                throw OAuthClientError.missingTokens
            }
        case .localForceRefresh:
            Logger.OAuthClient.log("Getting local tokens and force refresh")
            return try await refreshTokens()
        case .createIfNeeded:
            Logger.OAuthClient.log("Getting tokens and creating a new account if needed")
            if let localTokenContainer {
                Logger.OAuthClient.log("Local tokens found, expiry: \(localTokenContainer.decodedAccessToken.exp.value)")
                // An account existed before, recovering it and refreshing the tokens
                if localTokenContainer.decodedAccessToken.isExpired() {
                    Logger.OAuthClient.log("Local access token is expired, refreshing it")
                    let refreshedTokens = try await refreshTokens()
                    return refreshedTokens
                } else {
                    return localTokenContainer
                }
            } else {
                Logger.OAuthClient.log("Local token not found, creating a new account")
                // We don't have a token stored, create a new account
                let tokens = try await createAccount()
                // Save tokens
                tokenStorage.tokenContainer = tokens
                return tokens
            }
        }
    }

    /// Tries to retrieve the v1 auth token stored locally, if present performs a migration to v2 and removes the old token
    private func migrateLegacyTokenIfNeeded() async -> TokenContainer? {
        guard var legacyTokenStorage,
                let legacyToken = legacyTokenStorage.token else {
            return nil
        }

        Logger.OAuthClient.log("Migrating legacy token")
        do {
            let tokenContainer = try await exchange(accessTokenV1: legacyToken)
            Logger.OAuthClient.log("Tokens migrated successfully, removing legacy token")

            // Remove old token
            legacyTokenStorage.token = nil

            // Store new tokens
            tokenStorage.tokenContainer = tokenContainer

            return tokenContainer
        } catch {
            Logger.OAuthClient.error("Failed to migrate legacy token: \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: Create

    /// Create an accounts, stores all tokens and returns them
    private func createAccount() async throws -> TokenContainer {
        Logger.OAuthClient.log("Creating new account")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorize(codeChallenge: codeChallenge)
        let authCode = try await authService.createAccount(authSessionID: authSessionID)
        let tokenContainer = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        Logger.OAuthClient.log("New account created successfully")
        return tokenContainer
    }

    // MARK: Activate

    /*
    /// Helper, single use
    public class EmailAccountActivator {

        private let oAuthClient: any OAuthClient
        private var email: String?
        private var authSessionID: String?
        private var codeVerifier: String?

        public init(oAuthClient: any OAuthClient) {
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

    public func requestOTP(email: String) async throws -> (authSessionID: String, codeVerifier: String) {
        Logger.OAuthClient.log("Requesting OTP")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorize(codeChallenge: codeChallenge)
        try await authService.requestOTP(authSessionID: authSessionID, emailAddress: email)
        return (authSessionID, codeVerifier) // to be used in activate(withOTP or activate(withPlatformSignature
    }

    public func activate(withOTP otp: String, email: String, codeVerifier: String, authSessionID: String) async throws {
        Logger.OAuthClient.log("Activating with OTP")
        let authCode = try await authService.login(withOTP: otp, authSessionID: authSessionID, email: email)
        try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
    }
     */

    public func activate(withPlatformSignature signature: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Activating with platform signature")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorize(codeChallenge: codeChallenge)
        let authCode = try await authService.login(withSignature: signature, authSessionID: authSessionID)
        let tokens = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        tokenStorage.tokenContainer = tokens
        Logger.OAuthClient.log("Activation completed")
        return tokens
    }

    // MARK: Refresh

    private func refreshTokens() async throws -> TokenContainer {
        Logger.OAuthClient.log("Refreshing tokens")
        guard let refreshToken = tokenStorage.tokenContainer?.refreshToken else {
            throw OAuthClientError.missingRefreshToken
        }

        do {
            let refreshTokenResponse = try await authService.refreshAccessToken(clientID: Constants.clientID, refreshToken: refreshToken)
            let refreshedTokens = try await decode(accessToken: refreshTokenResponse.accessToken, refreshToken: refreshTokenResponse.refreshToken)
            Logger.OAuthClient.log("Tokens refreshed: \(refreshedTokens.debugDescription)")
            tokenStorage.tokenContainer = refreshedTokens
            return refreshedTokens
        } catch OAuthServiceError.authAPIError(let code) {
            if code == OAuthRequest.BodyErrorCode.invalidTokenRequest {
                Logger.OAuthClient.error("Failed to refresh token")
                throw OAuthClientError.deadToken
            } else {
                Logger.OAuthClient.error("Failed to refresh token: \(code.rawValue, privacy: .public), \(code.description, privacy: .public)")
                throw OAuthServiceError.authAPIError(code: code)
            }
        } catch {
            Logger.OAuthClient.error("Failed to refresh token: \(error, privacy: .public)")
            throw error
        }
    }

    // MARK: Exchange V1 to V2 token

    public func exchange(accessTokenV1: String) async throws -> TokenContainer {
        Logger.OAuthClient.log("Exchanging access token V1 to V2")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorize(codeChallenge: codeChallenge)
        let authCode = try await authService.exchangeToken(accessTokenV1: accessTokenV1, authSessionID: authSessionID)
        let tokens = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        return tokens
    }

    // MARK: Logout

    public func logout() async throws {
        Logger.OAuthClient.log("Logging out")
        if let token = tokenStorage.tokenContainer?.accessToken {
            try await authService.logout(accessToken: token)
        }
        removeLocalAccount()
    }

    public func removeLocalAccount() {
        Logger.OAuthClient.log("Removing local account")
        tokenStorage.tokenContainer = nil
        legacyTokenStorage?.token = nil
    }

    /* MARK: Edit account

    /// Helper, single use
    public class AccountEditor {

        private let oAuthClient: any OAuthClient
        private var hashString: String?
        private var email: String?

        public init(oAuthClient: any OAuthClient) {
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

    public func changeAccount(email: String?) async throws -> String {
        guard let token = tokensStorage.tokenContainer?.accessToken else {
            throw OAuthClientError.unauthenticated
        }
        let editAccountResponse = try await authService.editAccount(clientID: Constants.clientID, accessToken: token, email: email)
        return editAccountResponse.hash
    }

    public func confirmChangeAccount(email: String, otp: String, hash: String) async throws {
        guard let token = tokensStorage.tokenContainer?.accessToken else {
            throw OAuthClientError.unauthenticated
        }
        _ = try await authService.confirmEditAccount(accessToken: token, email: email, hash: hash, otp: otp)
    }
     */
}
