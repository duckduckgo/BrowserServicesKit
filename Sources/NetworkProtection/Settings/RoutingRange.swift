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
        // This is disabled because excluded routes seem to trump included routes, and our DNS
        // server's IP address lives in this range.
        // Ref: https://app.asana.com/0/1203708860857015/1206099277258514/f
        //
        // .range("10.0.0.0/8"     /* 255.0.0.0 */, description: "disabled for enforceRoutes"),
        .range("127.0.0.0/8"    /* 255.0.0.0 */, description: "Loopback"),
        .range("169.254.0.0/16" /* 255.255.0.0 */, description: "Link-local"),
        .range("224.0.0.0/4"    /* 240.0.0.0 */, description: "Multicast"),
        .range("240.0.0.0/4"    /* 240.0.0.0 */, description: "Class E"),
    ]

    public static let alwaysExcludedIPv6Ranges: [RoutingRange] = [
        // We need to figure out what will happen to these when
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
        .section("IPv4 - Local Network"),
        .range("10.0.0.0/8"     /* 255.0.0.0   */),
        .range("172.16.0.0/12"  /* 255.240.0.0 */),
        .range("192.168.0.0/16" /* 255.255.0.0 */),
    ]

    public static let publicNetworkRanges: [RoutingRange] = [
        .section("IPv4 - Public Routes"),
        .range("1.0.0.0/8"),
        .range("2.0.0.0/8"),
        .range("3.0.0.0/8"),
        .range("4.0.0.0/6"),
        .range("8.0.0.0/7"),
        .range("11.0.0.0/8"),
        .range("12.0.0.0/6"),
        .range("16.0.0.0/4"),
        .range("32.0.0.0/3"),
        .range("64.0.0.0/2"),
        .range("128.0.0.0/3"),
        .range("160.0.0.0/5"),
        .range("168.0.0.0/6"),
        .range("172.0.0.0/12"),
        .range("172.32.0.0/11"),
        .range("172.64.0.0/10"),
        .range("172.128.0.0/9"),
        .range("173.0.0.0/8"),
        .range("174.0.0.0/7"),
        .range("176.0.0.0/4"),
        .range("192.0.0.0/9"),
        .range("192.128.0.0/11"),
        .range("192.160.0.0/13"),
        .range("192.169.0.0/16"),
        .range("192.170.0.0/15"),
        .range("192.172.0.0/14"),
        .range("192.176.0.0/12"),
        .range("192.192.0.0/10"),
        .range("193.0.0.0/8"),
        .range("194.0.0.0/7"),
        .range("196.0.0.0/6"),
        .range("200.0.0.0/5"),
        .range("208.0.0.0/4")
    ]
}
