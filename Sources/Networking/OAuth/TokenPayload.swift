//
//  AccessTokenClaims.swift
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

public struct AccessTokenPayload: JWTPayload {
    let exp: ExpirationClaim
    let iat: IssuedAtClaim
    let sub: SubjectClaim
    let aud: AudienceClaim
    let iss: IssuerClaim
    let jti: IDClaim
    let scope: String
    let api: String // always v2
    let email: String // Can it be nil?
    let entitlements: [TokenPayloadEntitlement]

    public func verify(using signer: JWTKit.JWTSigner) throws {
        try self.exp.verifyNotExpired()
        if self.scope != "privacypro" {
            throw TokenPayloadError.InvalidTokenScope
        }
    }
}

public struct RefreshTokenPayload: JWTPayload {
    let exp: Int
    let iat: Int
    let sub: String
    let aud: String
    let iss: String
    let jti: String
    let scope: String
    let api: String

    public func verify(using signer: JWTKit.JWTSigner) throws {
        try self.exp.verifyNotExpired()
        if self.scope != "refresh" {
            throw TokenPayloadError.InvalidTokenScope
        }
    }
}

// Token Entitlement struct
public struct TokenPayloadEntitlement: Codable {
    let product: String
    let name: String
}
