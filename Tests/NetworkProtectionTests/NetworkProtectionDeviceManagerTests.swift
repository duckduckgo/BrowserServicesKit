//
//  NetworkProtectionDeviceManagerTests.swift
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
import XCTest
@testable import NetworkProtection
@testable import NetworkProtectionTestUtils

final class NetworkProtectionDeviceManagerTests: XCTestCase {
    var tokenStore: NetworkProtectionTokenStoreMock!
    var keyStore: NetworkProtectionKeyStoreMock!
    var networkClient: MockNetworkProtectionClient!
    var temporaryURL: URL!
    var serverListStore: NetworkProtectionServerListFileSystemStore!
    var manager: NetworkProtectionDeviceManager!

    override func setUp() {
        super.setUp()
        tokenStore = NetworkProtectionTokenStoreMock()
        tokenStore.token = "initialtoken"
        keyStore = NetworkProtectionKeyStoreMock()
        networkClient = MockNetworkProtectionClient()
        temporaryURL = temporaryFileURL()
        serverListStore = NetworkProtectionServerListFileSystemStore(fileURL: temporaryURL, errorEvents: nil)
        manager = NetworkProtectionDeviceManager(
            networkClient: networkClient,
            tokenStore: tokenStore,
            keyStore: keyStore,
            serverListStore: serverListStore,
            errorEvents: nil
        )
    }

    override func tearDown() {
        tokenStore = nil
        keyStore = nil
        temporaryURL = nil
        serverListStore = nil
        manager = nil
        networkClient = nil
        super.tearDown()
    }

    func testDeviceManager() async {
        let server = NetworkProtectionServer.mockRegisteredServer
        networkClient.stubRegister = .success([server])

        let configuration: (TunnelConfiguration, NetworkProtectionServerInfo)

        do {
            configuration = try await manager.generateTunnelConfiguration(selectionMethod: .automatic)
        } catch {
            XCTFail("Unexpected error \(error.localizedDescription)")
            return
        }

        // Check that the device manager created a private key
        XCTAssertTrue((try? keyStore.storedPrivateKey()) != nil)

        // Check that the server list store was given a server list
        XCTAssertEqual((try? serverListStore.storedNetworkProtectionServerList()), [.mockRegisteredServer])

        XCTAssertEqual(configuration.0.interface.privateKey, try? keyStore.storedPrivateKey())
    }

    func testWhenGeneratingTunnelConfig_AndNoServersAreStored_ThenPrivateKeyIsCreated_AndRegisterEndpointIsCalled() async {
        let server = NetworkProtectionServer.mockBaseServer
        let registeredServer = NetworkProtectionServer.mockRegisteredServer

        networkClient.stubGetServers = .success([server])
        networkClient.stubRegister = .success([registeredServer])

        XCTAssertNil(try? keyStore.storedPrivateKey())
        XCTAssertEqual(try? serverListStore.storedNetworkProtectionServerList(), [])
        XCTAssertNil(networkClient.spyRegister)

        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic)

        XCTAssertNotNil(try? keyStore.storedPrivateKey())
        XCTAssertEqual(try? serverListStore.storedNetworkProtectionServerList(), [registeredServer])
        XCTAssertNotNil(networkClient.spyRegister)
    }

    func testWhenGeneratingTunnelConfig_AndServerSelectionIsUsingLocation_MakesRequestWithCountryAndCity() async {
        let server = NetworkProtectionServer.mockBaseServer
        networkClient.stubRegister = .success([server])

        let preferredLocation = NetworkProtectionSelectedLocation(country: "Some country", city: "Some city")
        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .preferredLocation(preferredLocation))

        XCTAssertEqual(networkClient.spyRegister?.requestBody.city, preferredLocation.city)
        XCTAssertEqual(networkClient.spyRegister?.requestBody.country, preferredLocation.country)
    }

    func testWhenGeneratingTunnelConfig_AndServerSelectionIsUsingPrerredServer_MakesRequestWithServer() async {
        let server = NetworkProtectionServer.mockBaseServer
        networkClient.stubRegister = .success([server])

        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .preferredServer(serverName: server.serverName))

        XCTAssertEqual(networkClient.spyRegister?.requestBody.server, server.serverName)
    }

    func testWhenGeneratingTunnelConfig_storedAuthTokenIsInvalidOnGettingServers_deletesToken() async {
        _ = NetworkProtectionServer.mockRegisteredServer
        networkClient.stubRegister = .failure(.invalidAuthToken)

        XCTAssertNotNil(tokenStore.token)

        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic)

        XCTAssertNil(tokenStore.token)
    }

    func testWhenGeneratingTunnelConfig_storedAuthTokenIsInvalidOnRegisteringServer_deletesToken() async {
        networkClient.stubRegister = .failure(.invalidAuthToken)

        XCTAssertNotNil(tokenStore.token)

        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic)

        XCTAssertNil(tokenStore.token)
    }

    func testDecodingServers() throws {
        let servers1 = try JSONDecoder().decode([NetworkProtectionServer].self, from: TestData.mockServers)
        XCTAssertEqual(servers1.count, 6)

        let servers2 = try JSONDecoder().decode([NetworkProtectionServer].self, from: TestData.mockServers2)
        XCTAssertEqual(servers2.count, 6)
    }

}

extension NetworkProtectionDeviceManager {

    func generateTunnelConfiguration(selectionMethod: NetworkProtectionServerSelectionMethod) async throws -> (TunnelConfiguration, NetworkProtectionServerInfo) {
        try await generateTunnelConfiguration(selectionMethod: selectionMethod, includedRoutes: [], excludedRoutes: [], isKillSwitchEnabled: false)
    }

}
