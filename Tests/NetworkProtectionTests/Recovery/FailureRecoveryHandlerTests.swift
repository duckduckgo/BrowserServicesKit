//
//  FailureRecoveryHandlerTests.swift
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

import XCTest
@testable import NetworkProtection
import NetworkProtectionTestUtils

final class FailureRecoveryHandlerTests: XCTestCase {
    private var deviceManager: MockNetworkProtectionDeviceManagement!
    private var failureRecoveryHandler: FailureRecoveryHandler!

    override func setUp() {
        super.setUp()
        deviceManager = MockNetworkProtectionDeviceManagement()
        failureRecoveryHandler = FailureRecoveryHandler(deviceManager: deviceManager)
    }

    override func tearDown() {
        deviceManager = nil
        failureRecoveryHandler = nil
        super.tearDown()
    }

    func testAttemptRecovery_callsDeviceManagerWithExpectedValues() async {
        let expectedServerName = "expectedServerName"
        let server = NetworkProtectionServer.registeredServer(named: expectedServerName)
        let expectedIncludedRoutes: [IPAddressRange] = ["1.2.3.4/5"]
        let expectedExcludedRoutes: [IPAddressRange] = ["10.9.8.7/6"]
        let expectedKillSwitchEnabledValue = false
        _ = try? await failureRecoveryHandler.attemptRecovery(to: server, includedRoutes: expectedIncludedRoutes, excludedRoutes: expectedExcludedRoutes, isKillSwitchEnabled: expectedKillSwitchEnabledValue)
        guard let spyGenerateTunnelConfiguration = deviceManager.spyGenerateTunnelConfiguration else {
            XCTFail("attemptRecovery not called")
            return
        }
        XCTAssertEqual(spyGenerateTunnelConfiguration.includedRoutes, expectedIncludedRoutes)
        XCTAssertEqual(spyGenerateTunnelConfiguration.excludedRoutes, expectedExcludedRoutes)
        XCTAssertEqual(spyGenerateTunnelConfiguration.isKillSwitchEnabled, expectedKillSwitchEnabledValue)

        guard case .failureRecovery(let serverName) = spyGenerateTunnelConfiguration.selectionMethod else {
            XCTFail("Expected selectionMethod to equal failureRecover. Got \(spyGenerateTunnelConfiguration.selectionMethod)")
            return
        }
        XCTAssertEqual(serverName, expectedServerName)
    }

    func testAttemptRecovery_configFetchFailsWithNetPError_throwsConfigGenerationError() async {
        let stubbedError = NetworkProtectionError.failedToEncodeRegisterKeyRequest
        deviceManager.stubGenerateTunnelConfigurationError = stubbedError

        do {
            _ = try await failureRecoveryHandler.attemptRecovery(to: .mockRegisteredServer, includedRoutes: [], excludedRoutes: [], isKillSwitchEnabled: true)
            XCTFail("Expected error to be thrown")
        } catch {
            guard case FailureRecoveryError.configGenerationError(let underlyingError) = error else {
                XCTFail("Expected configGenerationError, got \(error)")
                return
            }
            guard case NetworkProtectionError.failedToEncodeRegisterKeyRequest = underlyingError else {
                XCTFail("Expected underlying error to match stubbed")
                return
            }
        }
    }

    func testAttemptRecovery_serverNameDifferentFromPreviousServerName_returnsNewConfigAndServer() async throws {
        let lastServerName = "oldServerName"
        let lastServer = NetworkProtectionServer.registeredServer(named: lastServerName)
        let newServerName = "newServerName"
        let expectedServer = NetworkProtectionServer.registeredServer(named: newServerName)
        let expectedConfig = TunnelConfiguration.make(named: newServerName)

        deviceManager.stubGenerateTunnelConfiguration = (
            tunnelConfig: expectedConfig,
            server: expectedServer
        )

        let result = try await failureRecoveryHandler.attemptRecovery(to: lastServer, includedRoutes: [], excludedRoutes: [], isKillSwitchEnabled: true)

        XCTAssertEqual(expectedConfig, result.tunnelConfig)
        XCTAssertEqual(expectedServer, result.server)
    }

    func testAttemptRecovery_allowedIPsDiffersFromPreviousAllowedIPs_returnsNewConfigAndServer() async throws {
        let lastAndNewServerName = "previousAndNewServerName"
        let lastServer = NetworkProtectionServer.registeredServer(named: lastAndNewServerName, allowedIPs: ["1.2.3.4/5", "6.7.8.9/10"])
        let newServer = NetworkProtectionServer.registeredServer(named: lastAndNewServerName, allowedIPs: ["10.9.8.7/6", "5.4.3.2/1"])
        let expectedConfig = TunnelConfiguration.make(named: lastAndNewServerName)

        deviceManager.stubGenerateTunnelConfiguration = (
            tunnelConfig: expectedConfig,
            server: newServer
        )

        let result = try await failureRecoveryHandler.attemptRecovery(to: lastServer, includedRoutes: [], excludedRoutes: [], isKillSwitchEnabled: true)

        XCTAssertEqual(expectedConfig, result.tunnelConfig)
        XCTAssertEqual(newServer, result.server)
    }

    func testAttemptRecovery_lastAndNewServerNamesAndAllowedIPsAreEqual_throwsNoRecoveryNecessaryError() async throws {
        let lastAndNewServerName = "previousAndNewServerName"
        let lastAndNewAllowedIPs = ["1.2.3.4/5", "10.9.8.7/6"]
        let lastServer = NetworkProtectionServer.registeredServer(named: lastAndNewServerName, allowedIPs: lastAndNewAllowedIPs)
        let newServer = NetworkProtectionServer.registeredServer(named: lastAndNewServerName, allowedIPs: lastAndNewAllowedIPs)

        deviceManager.stubGenerateTunnelConfiguration = (
            tunnelConfig: .make(named: lastAndNewServerName),
            server: newServer
        )

        do {
            _ = try await failureRecoveryHandler.attemptRecovery(to: lastServer, includedRoutes: [], excludedRoutes: [], isKillSwitchEnabled: true)
            XCTFail("Expected error to be thrown")
        } catch {
            guard case FailureRecoveryError.noRecoveryNecessary = error else {
                XCTFail("Expected noRecoveryNecessary, got \(error)")
                return
            }
        }
    }
}
