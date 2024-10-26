//
//  VPNRoutingTableResolver.swift
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

/// Owns the responsibility of defining the routing table for the VPN.
///
/// This class is a bit limited in scope right now and only combines ``VPNSettings``
/// routing rules with the DNS settings, which can only be known with certainty at connection-time.
/// This class could be extended in the future to also factor in provider configurations, since
/// those are not taken into account in ``VPNSettings``.
///
struct VPNRoutingTableResolver {

    private let baseExcludedRoutes: [IPAddressRange]
    private let baseIncludedRoutes: [IPAddressRange]
    private let dnsSettings: NetworkProtectionDNSSettings
    private let server: NetworkProtectionServer

    init(baseIncludedRoutes: [IPAddressRange],
         baseExcludedRoutes: [IPAddressRange],
         server: NetworkProtectionServer,
         dnsSettings: NetworkProtectionDNSSettings) {

        self.baseExcludedRoutes = baseExcludedRoutes
        self.baseIncludedRoutes = baseIncludedRoutes
        self.dnsSettings = dnsSettings
        self.server = server
    }

    var excludedRoutes: [IPAddressRange] {
        baseExcludedRoutes
    }

    var includedRoutes: [IPAddressRange] {
        baseIncludedRoutes + dnsRoutes()
    }

    // MARK: - Included Routes: Dynamic inclusions

    private func dnsRoutes() -> [IPAddressRange] {
        switch dnsSettings {
        case .default:
            [IPAddressRange(address: server.serverInfo.internalIP, networkPrefixLength: 32)]
        case .custom(let serverIPs):
            serverIPs.map { serverIP in
                IPAddressRange(stringLiteral: serverIP)
            }
        }
    }
}
