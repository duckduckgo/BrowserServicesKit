//
//  NetworkProtectionDeviceManager.swift
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
import Common
import NetworkExtension

public enum NetworkProtectionServerSelectionMethod: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .automatic:
            "automatic"
        case .preferredServer(let serverName):
            "preferredServer: \(serverName)"
        case .avoidServer(let serverName):
            "avoidServer: \(serverName)"
        case .preferredLocation(let location):
            "preferredLocation: \(location)"
        }
    }

    case automatic
    case preferredServer(serverName: String)
    case avoidServer(serverName: String)
    case preferredLocation(NetworkProtectionSelectedLocation)
}

public protocol NetworkProtectionDeviceManagement {

    func generateTunnelConfiguration(selectionMethod: NetworkProtectionServerSelectionMethod,
                                     includedRoutes: [IPAddressRange],
                                     excludedRoutes: [IPAddressRange],
                                     isKillSwitchEnabled: Bool,
                                     regenerateKey: Bool) async throws -> (TunnelConfiguration, NetworkProtectionServerInfo)

}

public actor NetworkProtectionDeviceManager: NetworkProtectionDeviceManagement {
    private let networkClient: NetworkProtectionClient
    private let tokenStore: NetworkProtectionTokenStore
    private let keyStore: NetworkProtectionKeyStore
    private let serverListStore: NetworkProtectionServerListStore

    private let errorEvents: EventMapping<NetworkProtectionError>?

    public init(environment: VPNSettings.SelectedEnvironment,
                tokenStore: NetworkProtectionTokenStore,
                keyStore: NetworkProtectionKeyStore,
                serverListStore: NetworkProtectionServerListStore? = nil,
                errorEvents: EventMapping<NetworkProtectionError>?) {
        self.init(networkClient: NetworkProtectionBackendClient(environment: environment),
                  tokenStore: tokenStore,
                  keyStore: keyStore,
                  serverListStore: serverListStore,
                  errorEvents: errorEvents)
    }

    init(networkClient: NetworkProtectionClient,
         tokenStore: NetworkProtectionTokenStore,
         keyStore: NetworkProtectionKeyStore,
         serverListStore: NetworkProtectionServerListStore? = nil,
         errorEvents: EventMapping<NetworkProtectionError>?) {
        self.networkClient = networkClient
        self.tokenStore = tokenStore
        self.keyStore = keyStore
        self.serverListStore = serverListStore ?? NetworkProtectionServerListFileSystemStore(errorEvents: errorEvents)
        self.errorEvents = errorEvents
    }

    /// Requests a new server list from the backend and updates it locally.
    /// This method will return the remote server list if available, or the local server list if there was a problem with the service call.
    ///
    public func refreshServerList() async throws -> [NetworkProtectionServer] {
        guard let token = try? tokenStore.fetchToken() else {
            throw NetworkProtectionError.noAuthTokenFound
        }
        let servers = await networkClient.getServers(authToken: token)
        let completeServerList: [NetworkProtectionServer]

        switch servers {
        case .success(let serverList):
            completeServerList = serverList
        case .failure(let failure):
            handle(clientError: failure)
            return try serverListStore.storedNetworkProtectionServerList()
        }

        do {
            try serverListStore.store(serverList: completeServerList)
        } catch let error as NetworkProtectionServerListStoreError {
            errorEvents?.fire(error.networkProtectionError)
            // Intentionally not rethrowing as the failing call is not critical to provide
            // a working UX.
        } catch {
            errorEvents?.fire(.unhandledError(function: #function, line: #line, error: error))
            // Intentionally not rethrowing as the failing call is not critical to provide
            // a working UX.
        }

        return completeServerList
    }

    /// Registers the device with the Network Protection backend.
    ///
    /// The flow for registration is as follows:
    /// 1. Look for an existing private key, and if one does not exist then generate it and store it in the Keychain
    /// 2. If the key is new, register it with all backend servers and return a tunnel configuration + its server info
    /// 3. If the key already existed, look up the stored set of backend servers and check if the preferred server is registered. If not, register it, and return the tunnel configuration + server info.
    ///
    public func generateTunnelConfiguration(selectionMethod: NetworkProtectionServerSelectionMethod,
                                            includedRoutes: [IPAddressRange],
                                            excludedRoutes: [IPAddressRange],
                                            isKillSwitchEnabled: Bool,
                                            regenerateKey: Bool) async throws -> (TunnelConfiguration, NetworkProtectionServerInfo) {
        var keyPair: KeyPair

        if regenerateKey {
            keyPair = keyStore.newKeyPair()
        } else {
            keyPair = keyStore.currentKeyPair()
        }

        let (selectedServer, newExpiration) = try await register(keyPair: keyPair, selectionMethod: selectionMethod)

        // If we're regenerating the key, then we know at this point it has been successfully registered. It's now safe to replace the old key.
        if regenerateKey {
            keyStore.updateKeyPair(keyPair)
        }

        if let newExpiration {
            keyPair = keyStore.updateKeyPairExpirationDate(newExpiration)
        }

        do {
            let configuration = try tunnelConfiguration(interfacePrivateKey: keyPair.privateKey,
                                                        server: selectedServer,
                                                        includedRoutes: includedRoutes,
                                                        excludedRoutes: excludedRoutes,
                                                        isKillSwitchEnabled: isKillSwitchEnabled)
            return (configuration, selectedServer.serverInfo)
        } catch let error as NetworkProtectionError {
            errorEvents?.fire(error)
            throw error
        } catch {
            errorEvents?.fire(.unhandledError(function: #function, line: #line, error: error))
            throw error
        }
    }

    // Registers the client with a server following the specified server selection method.  Returns the precise server that was selected and the keyPair to use
    // for the tunnel configuration.
    //
    // - Parameters:
    //     - selectionMethod: the server selection method
    //     - keyPair: the key pair that was used to register with the server, and that should be used to configure the tunnel
    //
    // - Throws:`NetworkProtectionError`
    private func register(keyPair: KeyPair,
                          selectionMethod: NetworkProtectionServerSelectionMethod) async throws -> (server: NetworkProtectionServer,
                                                                                                    newExpiration: Date?) {

        guard let token = try? tokenStore.fetchToken() else { throw NetworkProtectionError.noAuthTokenFound }

        let serverSelection: RegisterServerSelection
        let excludedServerName: String?

        switch selectionMethod {
        case .automatic:
            serverSelection = .automatic
            excludedServerName = nil
        case .preferredServer(let serverName):
            serverSelection = .server(name: serverName)
            excludedServerName = nil
        case .avoidServer(let serverToAvoid):
            serverSelection = .automatic
            excludedServerName = serverToAvoid
        case .preferredLocation(let location):
            serverSelection = .location(country: location.country, city: location.city)
            excludedServerName = nil
        }

        let requestBody = RegisterKeyRequestBody(publicKey: keyPair.publicKey,
                                                 serverSelection: serverSelection)

        let registeredServersResult = await networkClient.register(authToken: token,
                                                                   requestBody: requestBody)
        let selectedServer: NetworkProtectionServer

        switch registeredServersResult {
        case .success(let registeredServers):
            do {
                try serverListStore.store(serverList: registeredServers)
            } catch let error as NetworkProtectionServerListStoreError {
                errorEvents?.fire(error.networkProtectionError)
                // Intentionally not rethrowing, as this failure is not critical for this method
            } catch {
                errorEvents?.fire(.unhandledError(function: #function, line: #line, error: error))
                // Intentionally not rethrowing, as this failure is not critical for this method
            }

            guard let registeredServer = registeredServers.first(where: { $0.serverName != excludedServerName }) else {
                // If we're looking to exclude a server we should have a few other options available.  If we can't find any
                // then it means theres an inconsistency in the server list that was returned.
                errorEvents?.fire(NetworkProtectionError.serverListInconsistency)

                let cachedServer = try cachedServer(registeredWith: keyPair)
                return (cachedServer, nil)
            }

            selectedServer = registeredServer
            return (selectedServer, selectedServer.expirationDate)
        case .failure(let error):
            handle(clientError: error)

            let cachedServer = try cachedServer(registeredWith: keyPair)
            return (cachedServer, nil)
        }
    }

    /// Retrieves the first cached server that's registered with the specified key pair.
    ///
    private func cachedServer(registeredWith keyPair: KeyPair) throws -> NetworkProtectionServer {
        do {
            guard let server = try serverListStore.storedNetworkProtectionServerList().first(where: {
                $0.isRegistered(with: keyPair.publicKey)
            }) else {
                errorEvents?.fire(NetworkProtectionError.noServerListFound)
                throw NetworkProtectionError.noServerListFound
            }

            return server
        } catch let error as NetworkProtectionError {
            errorEvents?.fire(error)
            throw error
        } catch {
            errorEvents?.fire(NetworkProtectionError.unhandledError(function: #function, line: #line, error: error))
            throw NetworkProtectionError.unhandledError(function: #function, line: #line, error: error)
        }
    }

    // MARK: - Internal

    func server(in servers: [NetworkProtectionServer], matching name: String?) -> NetworkProtectionServer? {
        guard let name = name else {
            return nil
        }

        let matchingServer = servers.first { server in
            return server.serverName == name
        }

        return matchingServer
    }

    func tunnelConfiguration(interfacePrivateKey: PrivateKey,
                             server: NetworkProtectionServer,
                             includedRoutes: [IPAddressRange],
                             excludedRoutes: [IPAddressRange],
                             isKillSwitchEnabled: Bool) throws -> TunnelConfiguration {

        guard let allowedIPs = server.allowedIPs else {
            throw NetworkProtectionError.noServerRegistrationInfo
        }

        guard let serverPublicKey = PublicKey(base64Key: server.serverInfo.publicKey) else {
            throw NetworkProtectionError.couldNotGetPeerPublicKey
        }

        guard let serverEndpoint = server.serverInfo.endpoint else {
            throw NetworkProtectionError.couldNotGetPeerHostName
        }

        let peerConfiguration = peerConfiguration(serverPublicKey: serverPublicKey, serverEndpoint: serverEndpoint)

        guard let closestIP = allowedIPs.first, let interfaceAddressRange = IPAddressRange(from: closestIP) else {
            throw NetworkProtectionError.couldNotGetInterfaceAddressRange
        }

        let interface = interfaceConfiguration(privateKey: interfacePrivateKey,
                                               addressRange: interfaceAddressRange,
                                               includedRoutes: includedRoutes,
                                               excludedRoutes: excludedRoutes,
                                               dns: [DNSServer(address: server.serverInfo.internalIP)],
                                               isKillSwitchEnabled: isKillSwitchEnabled)

        return TunnelConfiguration(name: "Network Protection", interface: interface, peers: [peerConfiguration])
    }

    func peerConfiguration(serverPublicKey: PublicKey, serverEndpoint: Endpoint) -> PeerConfiguration {
        var peerConfiguration = PeerConfiguration(publicKey: serverPublicKey)

        peerConfiguration.allowedIPs = [IPAddressRange(from: "0.0.0.0/0")!, IPAddressRange(from: "::/0")!]
        peerConfiguration.endpoint = serverEndpoint

        return peerConfiguration
    }

    // swiftlint:disable function_parameter_count
    func interfaceConfiguration(privateKey: PrivateKey,
                                addressRange: IPAddressRange,
                                includedRoutes: [IPAddressRange],
                                excludedRoutes: [IPAddressRange],
                                dns: [DNSServer],
                                isKillSwitchEnabled: Bool) -> InterfaceConfiguration {
        var includedRoutes = includedRoutes
        // Tunnel doesn‘t work with ‘enforceRoutes‘ option when DNS IP/addressRange is in includedRoutes
        if !isKillSwitchEnabled {
            includedRoutes.append(contentsOf: dns.map { IPAddressRange(address: $0.address, networkPrefixLength: 32) })
            includedRoutes.append(addressRange)
        }
        return InterfaceConfiguration(privateKey: privateKey,
                                      addresses: [addressRange],
                                      includedRoutes: includedRoutes,
                                      excludedRoutes: excludedRoutes,
                                      listenPort: 51821,
                                      dns: dns)
    }
    // swiftlint:enable function_parameter_count

    private func handle(clientError: NetworkProtectionClientError) {
        if case .invalidAuthToken = clientError {
            try? tokenStore.deleteToken()
        }
        errorEvents?.fire(clientError.networkProtectionError)
    }
}
