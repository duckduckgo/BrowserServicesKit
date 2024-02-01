//
//  NetworkProtectionCodeRedemptionCoordinator.swift
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
import Common

public protocol NetworkProtectionCodeRedeeming {

    /// Redeems an invite code with the Network Protection backend and stores the resulting auth token
    func redeem(_ code: String) async throws

    /// Exchanges an access token for an auth token, and stores the resulting auth token
    func exchange(accessToken: String) async throws

}

/// Coordinates calls to the backend and oAuth token storage
public final class NetworkProtectionCodeRedemptionCoordinator: NetworkProtectionCodeRedeeming {
    private let networkClient: NetworkProtectionClient
    private let tokenStore: NetworkProtectionTokenStore
    private let versionStore: NetworkProtectionLastVersionRunStore
    private let isManualCodeRedemptionFlow: Bool
    private let errorEvents: EventMapping<NetworkProtectionError>

    convenience public init(environment: VPNSettings.SelectedEnvironment,
                            tokenStore: NetworkProtectionTokenStore,
                            versionStore: NetworkProtectionLastVersionRunStore = .init(),
                            isManualCodeRedemptionFlow: Bool = false,
                            errorEvents: EventMapping<NetworkProtectionError>) {
        self.init(networkClient: NetworkProtectionBackendClient(environment: environment, isSubscriptionEnabled: false),
                  tokenStore: tokenStore,
                  versionStore: versionStore,
                  isManualCodeRedemptionFlow: isManualCodeRedemptionFlow,
                  errorEvents: errorEvents)
    }

    init(networkClient: NetworkProtectionClient,
         tokenStore: NetworkProtectionTokenStore,
         versionStore: NetworkProtectionLastVersionRunStore = .init(),
         isManualCodeRedemptionFlow: Bool = false,
         errorEvents: EventMapping<NetworkProtectionError>) {
        self.networkClient = networkClient
        self.tokenStore = tokenStore
        self.versionStore = versionStore
        self.isManualCodeRedemptionFlow = isManualCodeRedemptionFlow
        self.errorEvents = errorEvents
    }

    public func redeem(_ code: String) async throws {
        let result = await networkClient.authenticate(withMethod: .inviteCode(code))
        switch result {
        case .success(let token):
            try tokenStore.store(token)
            // enable version checker on next run
            versionStore.lastVersionRun = AppVersion.shared.versionNumber

        case .failure(let error):
            if case .invalidInviteCode = error, isManualCodeRedemptionFlow {
                // Deliberately ignore cases where invalid invite codes are entered into the redemption form
                throw error
            } else {
                errorEvents.fire(error.networkProtectionError)
                throw error
            }
        }
    }

    public func exchange(accessToken code: String) async throws {
        let result = await networkClient.authenticate(withMethod: .subscription(code))
        switch result {
        case .success(let token):
            try tokenStore.store(token)
            // enable version checker on next run
            versionStore.lastVersionRun = AppVersion.shared.versionNumber

        case .failure(let error):
            errorEvents.fire(error.networkProtectionError)
            throw error
        }
    }

}
