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
import Network
import os.log

/// Owns the responsibility of defining the routing table for the VPN.
///
/// This class is a bit limited in scope right now and only combines ``VPNSettings``
/// routing rules with the DNS settings, which can only be known with certainty at connection-time.
/// This class could be extended in the future to also factor in provider configurations, since
/// those are not taken into account in ``VPNSettings``.
///
struct VPNRoutingTableResolver {

    private let dnsServers: [DNSServer]
    private let excludeLocalNetworks: Bool
    private let server: NetworkProtectionServer

    init(server: NetworkProtectionServer,
         dnsServers: [DNSServer],
         excludeLocalNetworks: Bool) {

        self.dnsServers = dnsServers
        self.excludeLocalNetworks = excludeLocalNetworks
        self.server = server
    }

    var excludedRoutes: [IPAddressRange] {
        var routes = alwaysExcludedIPv4Ranges + alwaysExcludedIPv6Ranges + serverRoutes()

        if excludeLocalNetworks {
            Logger.networkProtection.log("🤌 Excluding local networks")
            routes += localNetworkRanges
        }

        return routes
    }

    var includedRoutes: [IPAddressRange] {
        var routes = publicNetworkRanges + dnsRoutes()

        if !excludeLocalNetworks {
            Logger.networkProtection.log("🤌 Including local networks")
            routes += localNetworkRanges
        }

        return routes
    }

    // MARK: - Convenience

    private var alwaysExcludedIPv4Ranges: [IPAddressRange] {
        RoutingRange.alwaysExcludedIPv4Ranges.compactMap { entry in
            switch entry {
            case .section:
                return nil
            case .range(let range, _):
                return range
            }
        }
    }

    private var alwaysExcludedIPv6Ranges: [IPAddressRange] {
        RoutingRange.alwaysExcludedIPv6Ranges.compactMap { entry in
            switch entry {
            case .section:
                return nil
            case .range(let range, _):
                return range
            }
        }
    }

    private var localNetworkRanges: [IPAddressRange] {
        RoutingRange.localNetworkRanges.compactMap { entry in
            switch entry {
            case .section:
                // Nothing to map
                return nil
            case .range(let range, _):
                return range
            }
        }
    }

    private var publicNetworkRanges: [IPAddressRange] {
        RoutingRange.publicNetworkRanges.compactMap { entry in
            switch entry {
            case .section:
                // Nothing to map
                return nil
            case .range(let range, _):
                return range
            }
        }
    }

    // MARK: - Dynamic routes

    private func serverRoutes() -> [IPAddressRange] {
        server.serverInfo.ips.map { anyIP in
            IPAddressRange(address: anyIP.ipAddress, networkPrefixLength: 32)
        }
    }

    // MARK: - Included Routes

    private func dnsRoutes() -> [IPAddressRange] {
        dnsServers.map { server in
            return IPAddressRange(address: server.address, networkPrefixLength: 32)
        }
    }
}
