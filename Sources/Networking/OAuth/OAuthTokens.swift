//
//  OAuthTokens.swift
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
import JWTKit

enum TokenPayloadError: Error {
    case InvalidTokenScope
}

public struct JWTAccessToken: JWTPayload {
    let exp: ExpirationClaim
    let iat: IssuedAtClaim
    let sub: SubjectClaim
    let aud: AudienceClaim
    let iss: IssuerClaim
    let jti: IDClaim
    let scope: String
    let api: String // always v2
    let email: String?
    let entitlements: [EntitlementPayload]

    public func verify(using signer: JWTKit.JWTSigner) throws {
        try self.exp.verifyNotExpired()
        if self.scope != "privacypro" {
            throw TokenPayloadError.InvalidTokenScope
        }
    }

    public func isExpired() -> Bool {
        do {
            try self.exp.verifyNotExpired()
        } catch {
            return true
        }
        return false
    }

    public var externalID: String {
        sub.value
    }
}

public struct JWTRefreshToken: JWTPayload {
    let exp: ExpirationClaim
    let iat: IssuedAtClaim
    let sub: SubjectClaim
    let aud: AudienceClaim
    let iss: IssuerClaim
    let jti: IDClaim
    let scope: String
    let api: String

    public func verify(using signer: JWTKit.JWTSigner) throws {
        try self.exp.verifyNotExpired()
        if self.scope != "refresh" {
            throw TokenPayloadError.InvalidTokenScope
        }
    }
}

public struct EntitlementPayload: Codable {
    let product: SubscriptionEntitlement // Can expand in future
    let name: String // always `subscriber`

    public enum SubscriptionEntitlement: String, Codable {
        case networkProtection = "Network Protection"
        case dataBrokerProtection = "Data Broker Protection"
        case identityTheftRestoration = "Identity Theft Restoration"
        case unknown

        public init(from decoder: Decoder) throws {
            self = try Self(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ?? .unknown
        }
    }
}

public struct TokensContainer: Codable, Equatable {
    public  let accessToken: String
    public let refreshToken: String
    public let decodedAccessToken: JWTAccessToken
    public let decodedRefreshToken: JWTRefreshToken

    public static func == (lhs: TokensContainer, rhs: TokensContainer) -> Bool {
        lhs.accessToken == rhs.accessToken && lhs.refreshToken == rhs.refreshToken
    }
}
