//
//  NetworkProtectionError.swift
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

protocol NetworkProtectionErrorConvertible {
    var networkProtectionError: NetworkProtectionError { get }
}

public enum NetworkProtectionError: LocalizedError {
    // Tunnel configuration errors
    case noServerRegistrationInfo
    case couldNotSelectClosestServer
    case couldNotGetPeerPublicKey
    case couldNotGetPeerHostName
    case couldNotGetInterfaceAddressRange

    // Client errors
    case failedToFetchServerList(Error?)
    case failedToParseServerListResponse(Error)
    case failedToEncodeRegisterKeyRequest
    case failedToFetchRegisteredServers(Error?)
    case failedToParseRegisteredServersResponse(Error)
    case failedToEncodeRedeemRequest
    case invalidInviteCode
    case failedToRedeemInviteCode(Error?)
    case failedToRetrieveAuthToken(AuthenticationFailureResponse)
    case failedToParseRedeemResponse(Error)
    case invalidAuthToken
    case serverListInconsistency

    // Server list store errors
    case failedToEncodeServerList(Error)
    case failedToDecodeServerList(Error)
    case failedToWriteServerList(Error)
    case noServerListFound
    case couldNotCreateServerListDirectory(Error)
    case failedToReadServerList(Error)

    // Keychain errors
    case failedToCastKeychainValueToData(field: String)
    case keychainReadError(field: String, status: Int32)
    case keychainWriteError(field: String, status: Int32)
    case keychainDeleteError(status: Int32)

    // Wireguard errors
    case wireGuardCannotLocateTunnelFileDescriptor
    case wireGuardInvalidState
    case wireGuardDnsResolution
    case wireGuardSetNetworkSettings(Error)
    case startWireGuardBackend(Int32)

    // Auth errors
    case noAuthTokenFound

    // Unhandled error
    case unhandledError(function: String, line: Int, error: Error)

    public var errorDescription: String? {
        // This is probably not the most elegant error to show to a user but
        // it's a great way to get detailed reports for those cases we haven't
        // provided good descriptions for yet.
        return "NetworkProtectionError.\(String(describing: self))"
    }
}
