// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import Foundation
import Network

public struct InterfaceConfiguration: Equatable {
    public var privateKey: PrivateKey
    public var addresses = [IPAddressRange]()
    public var exclusions = [IPAddressRange]()
    public var listenPort: UInt16?
    public var mtu: UInt16?
    public var dns = [DNSServer]()
    public var dnsSearch = [String]()

    public init(privateKey: PrivateKey, addresses: [IPAddressRange], exclusions: [IPAddressRange], listenPort: UInt16? = nil, mtu: UInt16? = nil, dns: [DNSServer] = [], dnsSearch: [String] = []) {
        self.privateKey = privateKey
        self.addresses = addresses
        self.exclusions = exclusions
        self.listenPort = listenPort
        self.mtu = mtu
        self.dns = dns
        self.dnsSearch = dnsSearch
    }

}
