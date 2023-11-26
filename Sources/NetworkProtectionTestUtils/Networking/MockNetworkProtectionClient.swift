//
//  MockNetworkProtectionClient.swift
//  DuckDuckGo
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

import Foundation
@testable import NetworkProtection

// swiftlint:disable line_length
public final class MockNetworkProtectionClient: NetworkProtectionClient {
    public init() {
    }

    public var spyGetLocationsAuthToken: String?
    public var stubGetLocations: Result<[NetworkProtection.NetworkProtectionLocation], NetworkProtection.NetworkProtectionClientError> = .success([])
    public var getLocationsCalled: Bool {
        spyGetLocationsAuthToken != nil
    }

    public func getLocations(authToken: String) async -> Result<[NetworkProtection.NetworkProtectionLocation], NetworkProtection.NetworkProtectionClientError> {
        spyGetLocationsAuthToken = authToken
        return stubGetLocations
    }

    public var spyRedeemInviteCode: String?
    public var spyRedeemAccessToken: String?
    public var stubRedeem: Result<String, NetworkProtection.NetworkProtectionClientError> = .success("")
    public var redeemCalled: Bool {
        spyRedeemInviteCode != nil
    }

    public init(stubRedeem: Result<String, NetworkProtectionClientError> = .success(""),
                stubGetServers: Result<[NetworkProtectionServer], NetworkProtectionClientError> = .success([]),
                stubRegister: Result<[NetworkProtectionServer], NetworkProtectionClientError> = .success([])) {
        self.stubRedeem = stubRedeem
        self.stubGetServers = stubGetServers
        self.stubRegister = stubRegister
    }

    public func authenticate(
        withMethod method: NetworkProtection.NetworkProtectionAuthenticationMethod
    ) async -> Result<String, NetworkProtection.NetworkProtectionClientError> {
        switch method {
        case .inviteCode(let inviteCode):
            spyRedeemInviteCode = inviteCode
            return stubRedeem
        case .subscription(let accessToken):
            spyRedeemAccessToken = accessToken
            return stubRedeem
        }
    }

    public var spyGetServersAuthToken: String?
    public var stubGetServers: Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> = .success([])
    public var getServersCalled: Bool {
        spyGetServersAuthToken != nil
    }

    public func getServers(authToken: String) async -> Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> {
        spyGetServersAuthToken = authToken
        return stubGetServers
    }

    public var spyRegister: (authToken: String, requestBody: NetworkProtection.RegisterKeyRequestBody)?
    public var registerCalled: Bool {
        spyRegister != nil
    }
    public var stubRegister: Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> = .success([])

    public func register(authToken: String, requestBody: NetworkProtection.RegisterKeyRequestBody) async -> Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> {
        spyRegister = (authToken: authToken, requestBody: requestBody)
        return stubRegister
    }
}
// swiftlint:enable line_length
