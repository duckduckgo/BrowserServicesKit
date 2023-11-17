//
//  RoutingRange.swift
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

public enum RoutingRange {
    case section(String)
    case range(_ range: NetworkProtection.IPAddressRange, description: String? = nil)

    public static let alwaysExcludedIPv4Ranges: [RoutingRange] = [
        .section("IPv4 - Always Excluded"),
        .range("10.0.0.0/8"     /* 255.0.0.0 */, description: "disabled for enforceRoutes"),
        .range("100.64.0.0/16"  /* 255.255.0.0 */, description: "Shared Address Space"),
        .range("127.0.0.0/8"    /* 255.0.0.0 */, description: "Loopback"),
        .range("169.254.0.0/16" /* 255.255.0.0 */, description: "Link-local"),
        .range("224.0.0.0/4"    /* 240.0.0.0 */, description: "Multicast"),
        .range("240.0.0.0/4"    /* 240.0.0.0 */, description: "Class E"),

        .section("duckduckgo.com"),
        .range("52.142.124.215/32"),
        .range("52.250.42.157/32"),
        .range("40.114.177.156/32"),
    ]

    public static let alwaysExcludedIPv6Ranges: [RoutingRange] = [
        // When need to figure out what will happen to these when
        // excludeLocalNetworks is OFF.
        // For now though, I'm keeping these but leaving these always excluded
        // as IPv6 is out of scope.
        .section("IPv6 - Always Excluded"),
        .range("fe80::/10", description: "link local"),
        .range("ff00::/8", description: "multicast"),
        .range("fc00::/7", description: "local unicast"),
        .range("::1/128", description: "loopback"),
    ]

    public static let localNetworkRanges: [RoutingRange] = [
        .section("IPv4 - Local Routes"),
        .range("172.16.0.0/12"  /* 255.240.0.0 */),
        .range("192.168.0.0/16" /* 255.255.0.0 */),
    ]
}
