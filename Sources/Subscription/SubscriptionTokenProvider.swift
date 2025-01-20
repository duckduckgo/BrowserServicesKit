//
//  SubscriptionTokenProvider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Networking

/// The sole entity responsible of obtaining, storing and refreshing an OAuth Token
public protocol SubscriptionTokenProvider {

    /// Get a token container accordingly to the policy
    /// - Parameter policy: The policy that will be used to get the token, it effects the tokens source and validity
    /// - Returns: The TokenContainer
    /// - Throws: OAuthClientError.deadToken if the token is unrecoverable. SubscriptionEndpointServiceError.noData if the token is not available.
    @discardableResult
    func getTokenContainer(policy: TokensCachePolicy) async throws -> TokenContainer

    /// Exchange access token v1 for a access token v2
    /// - Parameter tokenV1: The Auth v1 access token
    /// - Returns: An auth v2 TokenContainer
    func exchange(tokenV1: String) async throws -> TokenContainer

    /// Used only from the Mac Packet Tunnel Provider when a token is received during configuration
    func adopt(tokenContainer: TokenContainer)

    /// Remove the stored token container
    func removeTokenContainer()
}
