//
//  AuthService.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Common
import Foundation

public protocol AuthServiceProtocol {
    func getAccessToken(token: String) async -> Result<AccessTokenResponse, APIServiceError>
    func validateToken(accessToken: String) async -> Result<ValidateTokenResponse, APIServiceError>
    func createAccount(emailAccessToken: String?) async -> Result<CreateAccountResponse, APIServiceError>
    func storeLogin(signature: String) async -> Result<StoreLoginResponse, APIServiceError>
}

public struct AccessTokenResponse: Decodable {
    public let accessToken: String
}

public struct ValidateTokenResponse: Decodable {
    public let account: Account

    public struct Account: Decodable {
        public let email: String?
        let entitlements: [Entitlement]
        public let externalID: String

        enum CodingKeys: String, CodingKey {
            case email, entitlements, externalID = "externalId" // no underscores due to keyDecodingStrategy = .convertFromSnakeCase
        }
    }
}

public struct CreateAccountResponse: Decodable {
    public let authToken: String
    public let externalID: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case authToken = "authToken", externalID = "externalId", status // no underscores due to keyDecodingStrategy = .convertFromSnakeCase
    }
}

public struct StoreLoginResponse: Decodable {
    public let authToken: String
    public let email: String
    public let externalID: String
    public let id: Int
    public let status: String

    enum CodingKeys: String, CodingKey {
        case authToken = "authToken", email, externalID = "externalId", id, status // no underscores due to keyDecodingStrategy = .convertFromSnakeCase
    }
}

// MARK: - Implementation

public struct AuthService: APIService, AuthServiceProtocol {

    let environment: SubscriptionServiceEnvironment

    var baseURL: URL {
        switch environment {
        case .production:
            URL(string: "https://quack.duckduckgo.com/api/auth")!
        case .staging:
            URL(string: "https://quackdev.duckduckgo.com/api/auth")!
        }
    }

    let session = {
        let configuration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: configuration)
    }()

    init(environment: SubscriptionServiceEnvironment) {
            self.environment = environment
    }

    // MARK: -

    public func getAccessToken(token: String) async -> Result<AccessTokenResponse, APIServiceError> {
        await executeAPICall(method: "GET", endpoint: "access-token", headers: makeAuthorizationHeader(for: token))
    }

    // MARK: -

    public func validateToken(accessToken: String) async -> Result<ValidateTokenResponse, APIServiceError> {
        await executeAPICall(method: "GET", endpoint: "validate-token", headers: makeAuthorizationHeader(for: accessToken))
    }

    // MARK: -

    public func createAccount(emailAccessToken: String?) async -> Result<CreateAccountResponse, APIServiceError> {
        var headers: [String: String]?

        if let emailAccessToken {
            headers = makeAuthorizationHeader(for: emailAccessToken)
        }

        return await executeAPICall(method: "POST", endpoint: "account/create", headers: headers)
    }

    public func storeLogin(signature: String) async -> Result<StoreLoginResponse, APIServiceError> {
        let bodyDict = ["signature": signature,
                        "store": "apple_app_store"]

        guard let bodyData = try? JSONEncoder().encode(bodyDict) else { return .failure(.encodingError) }
        return await executeAPICall(method: "POST", endpoint: "store-login", body: bodyData)
    }
}
