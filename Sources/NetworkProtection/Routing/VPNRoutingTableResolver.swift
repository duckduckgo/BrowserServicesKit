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

/// Owns the responsibility of defining the routing table for the VPN based on all the relevant
/// configuration options and values.
///
struct VPNRoutingTableResolver {

    private let baseExcludedRoutes: [IPAddressRange]
    private let baseIncludedRoutes: [IPAddressRange]
    private let dnsSettings: NetworkProtectionDNSSettings
    private let server: NetworkProtectionServer

    private static let localNetworks: [IPAddressRange] = {
        ["172.16.0.0/12", "192.168.0.0/16"]
    }()

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
        baseExcludedRoutes + Self.localNetworks
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
