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
        }
    }
}

public protocol TokensStoring {
    var tokensContainer: TokensContainer? { get set }
}

public enum TokensCachePolicy {
    /// The locally stored one as it is, valid or not
    case local
    /// The locally stored one refreshed
    case localValid
    /// Local refreshed, if doesn't exist create a new one
    case createIfNeeded
}

public protocol OAuthClient {

    // MARK: - Public

    var isUserAuthenticated: Bool { get }

    var currentTokensContainer: TokensContainer? { get }

    /// Returns a tokens container based on the policy
    /// - `.local`: returns what's in the storage, as it is, throws an error if no token is available
    /// - `.localValid`: returns what's in the storage, refreshes it if needed. throws an error if no token is available
    /// - `.createIfNeeded`: Returns a tokens container with unexpired tokens, creates a new account if needed
    /// All options store new or refreshed tokens via the tokensStorage
    func getTokens(policy: TokensCachePolicy) async throws -> TokensContainer

    /// Create an account, store all tokens and return them
    func createAccount() async throws -> TokensContainer

    // MARK: Activate

    /// Request an OTP for the provided email
    /// - Parameter email: The email to request the OTP for
    /// - Returns: A tuple containing the authSessionID and codeVerifier
    func requestOTP(email: String) async throws -> (authSessionID: String, codeVerifier: String)

    /// Activate the account with an OTP
    /// - Parameters:
    ///   - otp: The OTP received via email
    ///   - email: The email address
    ///   - codeVerifier: The codeVerifier
    ///   - authSessionID: The authentication session ID
    func activate(withOTP otp: String, email: String, codeVerifier: String, authSessionID: String) async throws

    /// Activate the account with a platform signature
    /// - Parameter signature: The platform signature
    /// - Returns: A container of tokens
    func activate(withPlatformSignature signature: String) async throws -> TokensContainer

    // MARK: Refresh

    /// Refresh the tokens and store the refreshed tokens
    /// - Returns: A container of refreshed tokens
    @discardableResult
    func refreshTokens() async throws -> TokensContainer

    // MARK: Exchange V1 to V2 token

    /// Exchange a V1 access token for a V2 token
    /// - Parameter accessTokenV1: The V1 access token
    /// - Returns: A container of tokens
    func exchange(accessTokenV1: String) async throws -> TokensContainer

    // MARK: Logout

    /// Logout by invalidating the current access token
    func logout() async throws

    // MARK: Edit account

    /// Change the email address of the account
    /// - Parameter email: The new email address
    /// - Returns: A hash string for verification
    func changeAccount(email: String?) async throws -> String

    /// Confirm the change of email address
    /// - Parameters:
    ///   - email: The new email address
    ///   - otp: The OTP received via email
    ///   - hash: The hash for verification
    func confirmChangeAccount(email: String, otp: String, hash: String) async throws
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
    public var tokensStorage: any TokensStoring

    public init(tokensStorage: any TokensStoring, authService: OAuthService) {
        self.tokensStorage = tokensStorage
        self.authService = authService
    }

    // MARK: - Internal

    @discardableResult
    private func getTokens(authCode: String, codeVerifier: String) async throws -> TokensContainer {
        Logger.OAuthClient.debug("Getting tokens")
        let getTokensResponse = try await authService.getAccessToken(clientID: Constants.clientID,
                                                             codeVerifier: codeVerifier,
                                                             code: authCode,
                                                             redirectURI: Constants.redirectURI)
        return try await decode(accessToken: getTokensResponse.accessToken, refreshToken: getTokensResponse.refreshToken)
    }

    private func getVerificationCodes() async throws -> (codeVerifier: String, codeChallenge: String) {
        Logger.OAuthClient.debug("Getting verification codes")
        let codeVerifier = OAuthCodesGenerator.codeVerifier
        guard let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: codeVerifier) else {
            Logger.OAuthClient.error("Failed to get verification codes")
            throw OAuthClientError.internalError("Failed to generate code challenge")
        }
        return (codeVerifier, codeChallenge)
    }

    private func decode(accessToken: String, refreshToken: String) async throws -> TokensContainer {
        Logger.OAuthClient.debug("Decoding tokens")
        let jwtSigners = try await authService.getJWTSigners()
        let decodedAccessToken = try jwtSigners.verify(accessToken, as: JWTAccessToken.self)
        let decodedRefreshToken = try jwtSigners.verify(refreshToken, as: JWTRefreshToken.self)

        return TokensContainer(accessToken: accessToken,
                               refreshToken: refreshToken,
                               decodedAccessToken: decodedAccessToken,
                               decodedRefreshToken: decodedRefreshToken)
    }

    // MARK: - Public

    public var isUserAuthenticated: Bool {
        tokensStorage.tokensContainer != nil
    }

    public var currentTokensContainer: TokensContainer? {
        tokensStorage.tokensContainer
    }

    /// Returns a tokens container based on the policy
    /// - `.local`: returns what's in the storage, as it is, throws an error if no token is available
    /// - `.localValid`: returns what's in the storage, refreshes it if needed. throws an error if no token is available
    /// - `.createIfNeeded`: Returns a tokens container with unexpired tokens, creates a new account if needed
    /// All options store new or refreshed tokens via the tokensStorage
    public func getTokens(policy: TokensCachePolicy) async throws -> TokensContainer {
        let storedTokens = tokensStorage.tokensContainer

        switch policy {
        case .local:
            Logger.OAuthClient.debug("Getting local tokens")
            if let storedTokens {
                Logger.OAuthClient.debug("Local tokens found, expiry: \(storedTokens.decodedAccessToken.exp.value)")
                return storedTokens
            } else {
                throw OAuthClientError.missingTokens
            }
        case .localValid: // TODO: Optimise code removing duplications
            Logger.OAuthClient.debug("Getting local tokens and refreshing them if needed")
            if let storedTokens {
                Logger.OAuthClient.debug("Local tokens found, expiry: \(storedTokens.decodedAccessToken.exp.value)")
                if storedTokens.decodedAccessToken.isExpired() {
                    Logger.OAuthClient.debug("Local access token is expired, refreshing it")
                    let refreshedTokens = try await refreshTokens()
                    tokensStorage.tokensContainer = refreshedTokens
                    return refreshedTokens
                } else {
                    return storedTokens
                }
            } else {
                throw OAuthClientError.missingTokens
            }
        case .createIfNeeded:
            Logger.OAuthClient.debug("Getting tokens and creating a new account if needed")
            if let storedTokens {
                Logger.OAuthClient.debug("Local tokens found, expiry: \(storedTokens.decodedAccessToken.exp.value)")
                // An account existed before, recovering it and refreshing the tokens
                if storedTokens.decodedAccessToken.isExpired() {
                    Logger.OAuthClient.debug("Local access token is expired, refreshing it")
                    let refreshedTokens = try await refreshTokens()
                    tokensStorage.tokensContainer = refreshedTokens
                    return refreshedTokens
                } else {
                    return storedTokens
                }
            } else {
                Logger.OAuthClient.debug("Local token not found, creating a new account")
                // We don't have a token stored, create a new account
                let tokens = try await createAccount()
                // Save tokens
                tokensStorage.tokensContainer = tokens
                return tokens
            }
        }
    }

    // MARK: Create

    /// Create an accounts, stores all tokens and returns them
    public func createAccount() async throws -> TokensContainer {
        Logger.OAuthClient.debug("Creating new account")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        let authCode = try await authService.createAccount(authSessionID: authSessionID)
        let tokens = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        Logger.OAuthClient.debug("New account created successfully")
        return tokens
    }

    // MARK: Activate

    /// Helper, single use // TODO: doc
    public class EmailAccountActivator {

        private let oAuthClient: any OAuthClient
        private var email: String? = nil
        private var authSessionID: String? = nil
        private var codeVerifier: String? = nil

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
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        try await authService.requestOTP(authSessionID: authSessionID, emailAddress: email)
        return (authSessionID, codeVerifier) // to be used in activate(withOTP or activate(withPlatformSignature
    }

    public func activate(withOTP otp: String, email: String, codeVerifier: String, authSessionID: String) async throws {
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
        Logger.OAuthClient.debug("Refreshing tokens")
        guard let refreshToken = tokensStorage.tokensContainer?.refreshToken else {
            throw OAuthClientError.missingRefreshToken
        }

        do {
            let refreshTokenResponse = try await authService.refreshAccessToken(clientID: Constants.clientID, refreshToken: refreshToken)
            let refreshedTokens = try await decode(accessToken: refreshTokenResponse.accessToken, refreshToken: refreshTokenResponse.refreshToken)
            return refreshedTokens
        } catch OAuthServiceError.authAPIError(let code) {
            // NOTE: If the client succeeds in making a refresh request but does not get the response, then the second refresh request will fail with `invalidTokenRequest` and the stored token will become unusable so the user will have to sign in again.
            if code == OAuthRequest.BodyErrorCode.invalidTokenRequest {
                Logger.OAuthClient.error("Failed to refresh token, logging out")

                tokensStorage.tokensContainer = nil

                let tokens = try await createAccount()
                tokensStorage.tokensContainer = tokens
                return tokens
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

    public func exchange(accessTokenV1: String) async throws -> TokensContainer {
        Logger.OAuthClient.debug("Exchanging access token V1 to V2")
        let (codeVerifier, codeChallenge) = try await getVerificationCodes()
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        let authCode = try await authService.exchangeToken(accessTokenV1: accessTokenV1, authSessionID: authSessionID)
        let tokens = try await getTokens(authCode: authCode, codeVerifier: codeVerifier)
        tokensStorage.tokensContainer = tokens
        return tokens
    }

    // MARK: Logout

    public func logout() async throws {
        Logger.OAuthClient.debug("Logging out")
        if let token = tokensStorage.tokensContainer?.accessToken {
            try await authService.logout(accessToken: token)
        }
        tokensStorage.tokensContainer = nil
    }

    // MARK: Edit account

    /// Helper, single use // TODO: doc
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
        guard let token = tokensStorage.tokensContainer?.accessToken else {
            throw OAuthClientError.unauthenticated
        }
        let editAccountResponse = try await authService.editAccount(clientID: Constants.clientID, accessToken: token, email: email)
        return editAccountResponse.hash
    }

    public func confirmChangeAccount(email: String, otp: String, hash: String) async throws {
        guard let token = tokensStorage.tokensContainer?.accessToken else {
            throw OAuthClientError.unauthenticated
        }
        _ = try await authService.confirmEditAccount(accessToken: token, email: email, hash: hash, otp: otp)
    }
}
