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

public enum OAuthClientError: Error {
    case InternalError(String)
}

public struct OAuthCLient {

    struct Constants {
        /// https://app.asana.com/0/1205784033024509/1207979495854201/f
        static let clientID = "f4311287-0121-40e6-8bbd-85c36daf1837"
        static let redirectURI = "com.duckduckgo:/authcb"
        static let availableScopes = [ "privacypro" ]

        static let productionBaseURL = URL(string: "https://duckduckgo.com")!
        static let stagingBaseURL = URL(string: "https://staging.duckduckgo.com")!
    }

    let authService: OAuthService

    init(authService: OAuthService = DefaultOAuthService(baseURL: Constants.productionBaseURL) ) {
        self.authService = authService
    }

    public func createAccount() async throws -> (accessToken: OAuthAccessToken, refreshToken: OAuthRefreshToken){

        let codeVerifier = OAuthCodesGenerator.codeVerifier
        guard let codeChallenge = OAuthCodesGenerator.codeChallenge(codeVerifier: codeVerifier) else {
            throw OAuthClientError.InternalError("Failed to generate code challenge")
        }
        let authSessionID = try await authService.authorise(codeChallenge: codeChallenge)
        let authCode = try await authService.createAccount(authSessionID: authSessionID)
        let getTokensResponse = try await authService.getAccessToken(clientID: Constants.clientID,
                                                             codeVerifier: codeVerifier,
                                                             code: authCode,
                                                             redirectURI: Constants.redirectURI)
        let jwtSigners = try await authService.getJWTSigners()
        let accessToken = try jwtSigners.verify(getTokensResponse.accessToken, as: OAuthAccessToken.self)
        let refreshToken = try jwtSigners.verify(getTokensResponse.refreshToken, as: OAuthRefreshToken.self)
        return (accessToken, refreshToken)
    }


}

