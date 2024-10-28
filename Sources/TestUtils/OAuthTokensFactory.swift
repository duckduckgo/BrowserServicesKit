//
//  OAuthTokensFactory.swift
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
@testable import Networking
@testable import JWTKit

public struct OAuthTokensFactory {

    // Helper function to create an expired JWTAccessToken
    public static func makeExpiredAccessToken() -> JWTAccessToken {
        return JWTAccessToken(
            exp: ExpirationClaim(value: Date().addingTimeInterval(-3600)), // Expired 1 hour ago
            iat: IssuedAtClaim(value: Date().addingTimeInterval(-7200)),
            sub: SubjectClaim(value: "test-subject"),
            aud: AudienceClaim(value: ["test-audience"]),
            iss: IssuerClaim(value: "test-issuer"),
            jti: IDClaim(value: "test-id"),
            scope: "privacypro",
            api: "v2",
            email: "test@example.com",
            entitlements: []
        )
    }

    // Helper function to create a valid JWTAccessToken with customizable scope
    public static func makeAccessToken(scope: String, email: String = "test@example.com") -> JWTAccessToken {
        return JWTAccessToken(
            exp: ExpirationClaim(value: Date().addingTimeInterval(3600)), // 1 hour from now
            iat: IssuedAtClaim(value: Date()),
            sub: SubjectClaim(value: "test-subject"),
            aud: AudienceClaim(value: ["test-audience"]),
            iss: IssuerClaim(value: "test-issuer"),
            jti: IDClaim(value: "test-id"),
            scope: scope,
            api: "v2",
            email: email,
            entitlements: []
        )
    }

    // Helper function to create a valid JWTRefreshToken with customizable scope
    public static func makeRefreshToken(scope: String) -> JWTRefreshToken {
        return JWTRefreshToken(
            exp: ExpirationClaim(value: Date().addingTimeInterval(3600)),
            iat: IssuedAtClaim(value: Date()),
            sub: SubjectClaim(value: "test-subject"),
            aud: AudienceClaim(value: ["test-audience"]),
            iss: IssuerClaim(value: "test-issuer"),
            jti: IDClaim(value: "test-id"),
            scope: scope,
            api: "v2"
        )
    }

    public static func makeValidTokensContainer() -> TokensContainer {
        return TokensContainer(accessToken: "accessToken",
                               refreshToken: "refreshToken",
                               decodedAccessToken: OAuthTokensFactory.makeAccessToken(scope: "privacypro"),
                               decodedRefreshToken: OAuthTokensFactory.makeRefreshToken(scope: "refresh"))
    }

    public static func makeExpiredTokensContainer() -> TokensContainer {
        return TokensContainer(accessToken: "accessToken",
                               refreshToken: "refreshToken",
                               decodedAccessToken: OAuthTokensFactory.makeExpiredAccessToken(),
                               decodedRefreshToken: OAuthTokensFactory.makeRefreshToken(scope: "refresh"))
    }
}
