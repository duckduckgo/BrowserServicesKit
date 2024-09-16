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
    var manager: NetworkProtectionDeviceManager!

    override func setUp() {
        super.setUp()
        tokenStore = NetworkProtectionTokenStoreMock()
        tokenStore.token = "initialtoken"
        keyStore = NetworkProtectionKeyStoreMock()
        networkClient = MockNetworkProtectionClient()
        temporaryURL = temporaryFileURL()

        manager = NetworkProtectionDeviceManager(
            networkClient: networkClient,
            tokenStore: tokenStore,
            keyStore: keyStore,
            errorEvents: nil
        )
    }

    override func tearDown() {
        tokenStore = nil
        keyStore = nil
        temporaryURL = nil
        manager = nil
        networkClient = nil
        super.tearDown()
    }

    func testDeviceManager() async {
        let server = NetworkProtectionServer.mockRegisteredServer
        networkClient.stubRegister = .success([server])

        let configuration: NetworkProtectionDeviceManager.GenerateTunnelConfigurationResult

        do {
            configuration = try await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: false)
        } catch {
            XCTFail("Unexpected error \(error.localizedDescription)")
            return
        }

        // Check that the device manager created a private key
        XCTAssertTrue((try? keyStore.storedPrivateKey()) != nil)

        XCTAssertEqual(configuration.0.interface.privateKey, try? keyStore.storedPrivateKey())
    }

    func testWhenGeneratingTunnelConfig_AndNoServersAreStored_ThenPrivateKeyIsCreated_AndRegisterEndpointIsCalled() async {
        let server = NetworkProtectionServer.mockBaseServer
        let registeredServer = NetworkProtectionServer.mockRegisteredServer

        networkClient.stubGetServers = .success([server])
        networkClient.stubRegister = .success([registeredServer])

        XCTAssertNil(try? keyStore.storedPrivateKey())
        XCTAssertNil(networkClient.spyRegister)

        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: false)

        XCTAssertNotNil(try? keyStore.storedPrivateKey())
        XCTAssertNotNil(networkClient.spyRegister)
    }

    func testWhenGeneratingTunnelConfig_AndServerSelectionIsUsingLocation_MakesRequestWithCountryAndCity() async {
        let server = NetworkProtectionServer.mockBaseServer
        networkClient.stubRegister = .success([server])

        let preferredLocation = NetworkProtectionSelectedLocation(country: "Some country", city: "Some city")
        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .preferredLocation(preferredLocation), regenerateKey: false)

        XCTAssertEqual(networkClient.spyRegister?.requestBody.city, preferredLocation.city)
        XCTAssertEqual(networkClient.spyRegister?.requestBody.country, preferredLocation.country)
    }

    func testWhenGeneratingTunnelConfig_AndServerSelectionIsUsingPrerredServer_MakesRequestWithServer() async {
        let server = NetworkProtectionServer.mockBaseServer
        networkClient.stubRegister = .success([server])

        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .preferredServer(serverName: server.serverName), regenerateKey: false)

        XCTAssertEqual(networkClient.spyRegister?.requestBody.server, server.serverName)
    }

    func testWhenGeneratingTunnelConfig_storedAuthTokenIsInvalidOnGettingServers_deletesToken() async {
        _ = NetworkProtectionServer.mockRegisteredServer
        networkClient.stubRegister = .failure(.invalidAuthToken)

        XCTAssertNotNil(tokenStore.token)

        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: false)

        XCTAssertNil(tokenStore.token)
    }

    func testWhenGeneratingTunnelConfig_storedAuthTokenIsInvalidOnRegisteringServer_deletesToken() async {
        networkClient.stubRegister = .failure(.invalidAuthToken)

        XCTAssertNotNil(tokenStore.token)

        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: false)

        XCTAssertNil(tokenStore.token)
    }

    func testDecodingServers() throws {
        let servers1 = try JSONDecoder().decode([NetworkProtectionServer].self, from: TestData.mockServers)
        XCTAssertEqual(servers1.count, 6)

        let servers2 = try JSONDecoder().decode([NetworkProtectionServer].self, from: TestData.mockServers2)
        XCTAssertEqual(servers2.count, 6)
    }

    func testWhenGeneratingTunnelConfiguration_AndKeyIsStillValid_AndKeyIsNotRegenerated_ThenKeyDoesNotChange() async {
        let server = NetworkProtectionServer.mockBaseServer
        let registeredServer = NetworkProtectionServer.mockRegisteredServer

        networkClient.stubGetServers = .success([server])
        networkClient.stubRegister = .success([registeredServer])

        XCTAssertNil(try? keyStore.storedPrivateKey())
        XCTAssertNil(networkClient.spyRegister)
        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: false)

        let firstKey = try? keyStore.storedPrivateKey()
        XCTAssertNotNil(firstKey)
        XCTAssertNotNil(networkClient.spyRegister)
        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: false)

        let secondKey = try? keyStore.storedPrivateKey()
        XCTAssertNotNil(secondKey)
        XCTAssertEqual(firstKey, secondKey) // Check that the key did NOT change
        XCTAssertNotNil(networkClient.spyRegister)
    }

    func testWhenGeneratingTunnelConfiguration_AndKeyIsStillValid_AndKeyIsRegenerated_ThenKeyChanges() async {
        let server = NetworkProtectionServer.mockBaseServer
        let registeredServer = NetworkProtectionServer.mockRegisteredServer

        networkClient.stubGetServers = .success([server])
        networkClient.stubRegister = .success([registeredServer])

        XCTAssertNil(try? keyStore.storedPrivateKey())
        XCTAssertNil(networkClient.spyRegister)
        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: false)

        let firstKey = try? keyStore.storedPrivateKey()
        XCTAssertNotNil(firstKey)
        XCTAssertNotNil(networkClient.spyRegister)
        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: true)

        let secondKey = try? keyStore.storedPrivateKey()
        XCTAssertNotNil(secondKey)
        XCTAssertNotEqual(firstKey, secondKey) // Check that the key changed
        XCTAssertNotNil(networkClient.spyRegister)
    }

    func testWhenGeneratingTunnelConfiguration_AndKeyIsStillValid_AndKeyIsRegenerated_AndRegistrationFails_ThenKeyDoesNotChange() async {
        let server = NetworkProtectionServer.mockBaseServer
        let registeredServer = NetworkProtectionServer.mockRegisteredServer

        networkClient.stubGetServers = .success([server])
        networkClient.stubRegister = .success([registeredServer])

        XCTAssertNil(try? keyStore.storedPrivateKey())
        XCTAssertNil(networkClient.spyRegister)
        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: false)

        let firstKey = try? keyStore.storedPrivateKey()
        XCTAssertNotNil(firstKey)
        XCTAssertNotNil(networkClient.spyRegister)

        networkClient.stubRegister = .failure(.failedToEncodeRegisterKeyRequest)
        _ = try? await manager.generateTunnelConfiguration(selectionMethod: .automatic, regenerateKey: true)

        let secondKey = try? keyStore.storedPrivateKey()
        XCTAssertNotNil(secondKey)
        XCTAssertEqual(firstKey, secondKey) // Check that the key did NOT change, even though we tried to regenerate it
        XCTAssertNotNil(networkClient.spyRegister)
    }
}

extension NetworkProtectionDeviceManager {

    func generateTunnelConfiguration(selectionMethod: NetworkProtectionServerSelectionMethod,
                                     regenerateKey: Bool) async throws -> NetworkProtectionDeviceManager.GenerateTunnelConfigurationResult {
        try await generateTunnelConfiguration(
            resolvedSelectionMethod: selectionMethod,
            includedRoutes: [],
            excludedRoutes: [],
            dnsSettings: .default,
            isKillSwitchEnabled: false,
            regenerateKey: regenerateKey
        )
    }

}
