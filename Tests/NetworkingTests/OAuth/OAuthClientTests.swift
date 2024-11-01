//
//  OAuthClientTests.swift
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

import XCTest
import TestUtils
@testable import Networking
import JWTKit

final class OAuthClientTests: XCTestCase {

    var oAuthClient: (any OAuthClient)!
    var mockOAuthService: MockOAuthService!
    var tokenStorage: MockTokenStorage!
    var legacyTokenStorage: MockLegacyTokenStorage!

    override func setUp() async throws {
        mockOAuthService = MockOAuthService()
        tokenStorage = MockTokenStorage()
        legacyTokenStorage = MockLegacyTokenStorage()
        oAuthClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                         legacyTokenStorage: legacyTokenStorage,
                                         authService: mockOAuthService)
    }

    override func tearDown() async throws {
        mockOAuthService = nil
        oAuthClient = nil
        tokenStorage = nil
        legacyTokenStorage = nil
    }

    // MARK: -

    func testUserNotAuthenticated() async throws {
        XCTAssertFalse(oAuthClient.isUserAuthenticated)
    }

    func testUserAuthenticated() async throws {
        tokenStorage.tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        XCTAssertTrue(oAuthClient.isUserAuthenticated)
    }

    func testCurrentTokenContainer() async throws {
        XCTAssertNil(oAuthClient.currentTokenContainer)
        tokenStorage.tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        XCTAssertNotNil(oAuthClient.currentTokenContainer)
    }

    // MARK: - Get tokens

    func testGetLocalTokenFail() async throws {
        let localContainer = try? await oAuthClient.getTokens(policy: .local)
        XCTAssertNil(localContainer)
    }

    func testGetLocalTokenSuccess() async throws {
        tokenStorage.tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        let localContainer = try? await oAuthClient.getTokens(policy: .local)
        XCTAssertNotNil(localContainer)
        XCTAssertFalse(localContainer!.decodedAccessToken.isExpired())
    }

    func testGetLocalTokenSuccessExpired() async throws {
        tokenStorage.tokenContainer = OAuthTokensFactory.makeExpiredTokenContainer()
        let localContainer = try? await oAuthClient.getTokens(policy: .local)
        XCTAssertNotNil(localContainer)
        XCTAssertTrue(localContainer!.decodedAccessToken.isExpired())
    }

    func testGetLocalTokenRefreshButExpired() async throws {
        // prepare mock service for token refresh
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        // Expired token
        mockOAuthService.refreshAccessTokenResponse = .success( OAuthTokensFactory.makeExpiredOAuthTokenResponse())

        // ask a fresh token, the local one is expired
        tokenStorage.tokenContainer = OAuthTokensFactory.makeExpiredTokenContainer()
        let localContainer = try? await oAuthClient.getTokens(policy: .localValid)
        XCTAssertNil(localContainer)
    }

/*
 public protocol OAuthClient {


     /// Returns a tokens container based on the policy
     /// - `.local`: returns what's in the storage, as it is, throws an error if no token is available
     /// - `.localValid`: returns what's in the storage, refreshes it if needed. throws an error if no token is available
     /// - `.createIfNeeded`: Returns a tokens container with unexpired tokens, creates a new account if needed
     /// All options store new or refreshed tokens via the tokensStorage
     func getTokens(policy: TokensCachePolicy) async throws -> TokenContainer

     /// Create an account, store all tokens and return them
     func createAccount() async throws -> TokenContainer

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
     func activate(withPlatformSignature signature: String) async throws -> TokenContainer

     // MARK: Refresh

     /// Refresh the tokens and store the refreshed tokens
     /// - Returns: A container of refreshed tokens
     @discardableResult
     func refreshTokens() async throws -> TokenContainer

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
 */
}
