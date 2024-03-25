//
//  NetworkProtectionError.swift
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

public enum NetworkProtectionError: LocalizedError, CustomNSError {
    // Tunnel configuration errors
    case noServerRegistrationInfo
    case couldNotSelectClosestServer
    case couldNotGetPeerPublicKey
    case couldNotGetPeerHostName
    case couldNotGetInterfaceAddressRange

    // Client errors
    case failedToFetchServerList(Error?)
    case failedToParseServerListResponse(Error)
    case failedToFetchLocationList(Error?)
    case failedToParseLocationListResponse(Error)
    case failedToEncodeRegisterKeyRequest
    case noResponseFromRegisterEndpoint
    case unexpectedStatusFromRegisterEndpoint(Error)
    case failedToFetchRegisteredServers(Error?)
    case failedToParseRegisteredServersResponse(Error)
    case failedToEncodeRedeemRequest
    case invalidInviteCode
    case noResponseFromRedeemEndpoint
    case unexpectedStatusFromRedeemEndpoint(Error)
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
    case keychainUpdateError(field: String, status: Int32)
    case keychainDeleteError(status: Int32)

    // Wireguard errors
    case wireGuardCannotLocateTunnelFileDescriptor
    case wireGuardInvalidState(reason: String)
    case wireGuardDnsResolution
    case wireGuardSetNetworkSettings(Error)
    case startWireGuardBackend(Int32)

    // Auth errors
    case noAuthTokenFound

    // Subscription errors
    case vpnAccessRevoked

    // Unhandled error
    case unhandledError(function: String, line: Int, error: Error)

    public static let errorDomain = "com.duckduckgo.NetworkProtectionError.domain"

    public var errorCode: Int {
        switch self {
            // 0+ - Tunnel configuration errors
        case .noServerRegistrationInfo: return 0
        case .couldNotSelectClosestServer: return 1
        case .couldNotGetPeerPublicKey: return 2
        case .couldNotGetPeerHostName: return 3
        case .couldNotGetInterfaceAddressRange: return 4
            // 100+ - Client errors
        case .failedToFetchServerList: return 100
        case .failedToParseServerListResponse: return 101
        case .failedToFetchLocationList: return 102
        case .failedToParseLocationListResponse: return 103
        case .failedToEncodeRegisterKeyRequest: return 104
        case .noResponseFromRegisterEndpoint: return 105
        case .unexpectedStatusFromRegisterEndpoint: return 106
        case .failedToFetchRegisteredServers: return 107
        case .failedToParseRegisteredServersResponse: return 108
        case .failedToEncodeRedeemRequest: return 109
        case .invalidInviteCode: return 110
        case .noResponseFromRedeemEndpoint: return 111
        case .unexpectedStatusFromRedeemEndpoint: return 112
        case .failedToRedeemInviteCode: return 113
        case .failedToRetrieveAuthToken: return 114
        case .failedToParseRedeemResponse: return 115
        case .invalidAuthToken: return 116
        case .serverListInconsistency: return 117
            // 200+ - Server list store errors
        case .failedToEncodeServerList: return 200
        case .failedToDecodeServerList: return 201
        case .failedToWriteServerList: return 202
        case .noServerListFound: return 203
        case .couldNotCreateServerListDirectory: return 204
        case .failedToReadServerList: return 205
            // 300+ - Keychain errors
        case .failedToCastKeychainValueToData: return 300
        case .keychainReadError: return 301
        case .keychainWriteError: return 302
        case .keychainUpdateError: return 303
        case .keychainDeleteError: return 304
            // 400+ - Wireguard errors
        case .wireGuardCannotLocateTunnelFileDescriptor: return 400
        case .wireGuardInvalidState: return 401
        case .wireGuardDnsResolution: return 402
        case .wireGuardSetNetworkSettings: return 403
        case .startWireGuardBackend: return 404
            // 500+ Auth errors
        case .noAuthTokenFound: return 500
            // 600+ Subscription errors
        case .vpnAccessRevoked: return 600
            // 700+ Unhandled errors
        case .unhandledError: return 700
        }
    }

    public var errorUserInfo: [String: Any] {
        switch self {
        case .noServerRegistrationInfo,
                .couldNotSelectClosestServer,
                .couldNotGetPeerPublicKey,
                .couldNotGetPeerHostName,
                .couldNotGetInterfaceAddressRange,
                .failedToEncodeRegisterKeyRequest,
                .noResponseFromRegisterEndpoint,
                .failedToEncodeRedeemRequest,
                .invalidInviteCode,
                .noResponseFromRedeemEndpoint,
                .failedToRetrieveAuthToken,
                .invalidAuthToken,
                .serverListInconsistency,
                .noServerListFound,
                .failedToCastKeychainValueToData,
                .keychainReadError,
                .keychainWriteError,
                .keychainUpdateError,
                .keychainDeleteError,
                .wireGuardCannotLocateTunnelFileDescriptor,
                .wireGuardInvalidState,
                .wireGuardDnsResolution,
                .startWireGuardBackend,
                .noAuthTokenFound,
                .vpnAccessRevoked:
            return [:]
        case .failedToFetchServerList(let error),
                .failedToFetchLocationList(let error),
                .failedToFetchRegisteredServers(let error),
                .failedToRedeemInviteCode(let error):
            guard let error else {
                return [:]
            }

            return [
                NSUnderlyingErrorKey: error
            ]
        case .failedToParseServerListResponse(let error),
                .failedToParseLocationListResponse(let error),
                .unexpectedStatusFromRegisterEndpoint(let error),
                .failedToParseRegisteredServersResponse(let error),
                .unexpectedStatusFromRedeemEndpoint(let error),
                .failedToParseRedeemResponse(let error),
                .failedToEncodeServerList(let error),
                .failedToDecodeServerList(let error),
                .failedToWriteServerList(let error),
                .couldNotCreateServerListDirectory(let error),
                .failedToReadServerList(let error),
                .wireGuardSetNetworkSettings(let error),
                .unhandledError(_, _, let error):
            return [
                NSUnderlyingErrorKey: error
            ]
        }
    }

    public var errorDescription: String? {
        // This is probably not the most elegant error to show to a user but
        // it's a great way to get detailed reports for those cases we haven't
        // provided good descriptions for yet.
        return "NetworkProtectionError.\(String(describing: self))"
    }
}
