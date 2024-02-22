//
//  ConnectionSessionUtilities.swift
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
import NetworkExtension

/// These are only usable from the App that owns the tunnel.
///
public class ConnectionSessionUtilities {

    /// Ideally we should remove these for iOS too.
    ///
    /// This has been deprecated in macOS to avoid making multiple calls to
    /// `NEPacketTunnelProviderManager.loadAllFromPreferences` since it causes notification
    /// degradation issues over time.  Also, I tried removing this for both platforms, but iOS doesn't have
    /// good ways to pass the tunnel controller where we need the session.
    ///
    /// Ref: https://app.asana.com/0/1203137811378537/1206513608690551/f
    ///
    @available(macOS, deprecated: 10.0, message: "Use NetworkProtectionTunnelController.activeSession instead.")
    public static func activeSession(networkExtensionBundleID: String) async throws -> NETunnelProviderSession? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()

        guard let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == networkExtensionBundleID
        }) else {
            // No active connection, this is acceptable
            return nil
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            // The active connection is not running, so there's no session, this is acceptable
            return nil
        }

        return session
    }

    /// Ideally we should remove these for iOS too.
    ///
    /// This has been deprecated in macOS to avoid making multiple calls to
    /// `NEPacketTunnelProviderManager.loadAllFromPreferences` since it causes notification
    /// degradation issues over time.  Also, I tried removing this for both platforms, but iOS doesn't have
    /// good ways to pass the tunnel controller where we need the session.
    ///
    /// Ref: https://app.asana.com/0/1203137811378537/1206513608690551/f
    ///
    @available(macOS, deprecated: 10.0, message: "Use NetworkProtectionTunnelController.activeSession instead.")
    public static func activeSession() async throws -> NETunnelProviderSession? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()

        guard let manager = managers.first else {
            // No active connection, this is acceptable
            return nil
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            // The active connection is not running, so there's no session, this is acceptable
            return nil
        }

        return session
    }

    /// Retrieves a session from a `NEVPNStatusDidChange` notification.
    ///
    public static func session(from notification: Notification) -> NETunnelProviderSession? {
        guard let session = (notification.object as? NETunnelProviderSession),
              session.manager is NETunnelProviderManager else {
            return nil
        }

        return session
    }
}

public extension NETunnelProviderSession {

    // MARK: - ExtensionMessage

    func sendProviderMessage(_ message: ExtensionMessage,
                             responseHandler: @escaping () -> Void) throws {
        try sendProviderMessage(message.rawValue) { _ in
            responseHandler()
        }
    }

    func sendProviderMessage<T: RawRepresentable>(_ message: ExtensionMessage,
                                                  responseHandler: @escaping (T?) -> Void) throws where T.RawValue == Data {
        try sendProviderMessage(message.rawValue) { response in
            responseHandler(response.flatMap(T.init(rawValue:)))
        }
    }

    func sendProviderRequest(_ request: ExtensionRequest) async throws {
        try await sendProviderMessage(.request(request))
    }

    func sendProviderRequest<T: RawRepresentable>(_ request: ExtensionRequest) async throws -> T? where T.RawValue == Data {

        try await sendProviderMessage(.request(request))
    }

    func sendProviderMessage(_ message: ExtensionMessage) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try sendProviderMessage(message) {
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func sendProviderMessage<T: RawRepresentable>(_ message: ExtensionMessage) async throws -> T? where T.RawValue == Data {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try sendProviderMessage(message) { response in
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
