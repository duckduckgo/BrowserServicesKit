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

public final class MockNetworkProtectionClient: NetworkProtectionClient {
    public var spyRedeemInviteCode: String?
    public var stubRedeem: Result<String, NetworkProtection.NetworkProtectionClientError> = .success("")

    public func redeem(inviteCode: String) async -> Result<String, NetworkProtection.NetworkProtectionClientError> {
        spyRedeemInviteCode = inviteCode
        return stubRedeem
    }

    public var spyGetServersAuthToken: String?
    public var stubGetServers: Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> = .success([])

    public func getServers(authToken: String) async -> Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> {
        spyGetServersAuthToken = authToken
        return stubGetServers
    }

    public var spyRegister: (authToken: String, publicKey: NetworkProtection.PublicKey, serverName: String?)?
    public var stubRegister: Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> = .success([])

    public func register(authToken: String, publicKey: NetworkProtection.PublicKey, withServerNamed serverName: String?) async -> Result<[NetworkProtection.NetworkProtectionServer], NetworkProtection.NetworkProtectionClientError> {
        spyRegister = (authToken: authToken, publicKey: publicKey, serverName: serverName)
        return stubRegister
    }
}
