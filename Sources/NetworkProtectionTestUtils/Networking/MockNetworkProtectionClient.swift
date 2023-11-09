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
import NetworkProtection

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
    public var stubRedeem: Result<String, NetworkProtection.NetworkProtectionClientError> = .success("")
    public var redeemCalled: Bool {
        spyRedeemInviteCode != nil
    }

    public func redeem(inviteCode: String) async -> Result<String, NetworkProtection.NetworkProtectionClientError> {
        spyRedeemInviteCode = inviteCode
        return stubRedeem
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

    // swiftlint:disable:next large_tuple
    public var spyRegister: (authToken: String, publicKey: NetworkProtection.PublicKey, serverName: String?)?
    public var registerCalled: Bool {
        spyRegister != nil
    }
    public var stubRegister: Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> = .success([])

    public func register(authToken: String, publicKey: NetworkProtection.PublicKey, withServerNamed serverName: String?) async -> Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> {
        spyRegister = (authToken: authToken, publicKey: publicKey, serverName: serverName)
        return stubRegister
    }
}
// swiftlint:enable line_length
