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

    private static let testConfig = FailureRecoveryHandler.RetryConfig(
        times: 0, // Means failure will bubble up after the first try
        initialDelay: .seconds(1),
        maxDelay: .seconds(30),
        factor: 2.0
    )

    override func setUp() {
        super.setUp()
        deviceManager = MockNetworkProtectionDeviceManagement()
        failureRecoveryHandler = FailureRecoveryHandler(deviceManager: deviceManager, retryConfig: Self.testConfig, eventHandler: { _ in })
        self.executionTimeAllowance = 5
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
        try? await failureRecoveryHandler.attemptRecovery(to: server, includedRoutes: expectedIncludedRoutes, excludedRoutes: expectedExcludedRoutes, isKillSwitchEnabled: expectedKillSwitchEnabledValue) {_ in }
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

    func testAttemptRecovery_configFetchFailsWithNetPError_throwsError() async {
        let stubbedError = NetworkProtectionError.failedToEncodeRegisterKeyRequest
        deviceManager.stubGenerateTunnelConfigurationError = stubbedError

        do {
            try await failureRecoveryHandler.attemptRecovery(to: .mockRegisteredServer, includedRoutes: [], excludedRoutes: [], isKillSwitchEnabled: true) {_ in }
            XCTFail("Expected error to be thrown")
        } catch {
            guard case FailureRecoveryError.reachedMaximumRetries(let lastError) = error else {
                XCTFail("Expected configGenerationError, got \(error)")
                return
            }
            guard case NetworkProtectionError.failedToEncodeRegisterKeyRequest = lastError else {
                XCTFail("Expected underlying error to match stubbed")
                return
            }
        }
    }

    func testAttemptRecovery_serverNameDifferentFromPreviousServerName_callsConfigUpdateWithNewConfigAndServer() async throws {
        let lastServerName = "oldServerName"
        let newServerName = "newServerName"
        let lastAndNewAllowedIPs = ["1.2.3.4/5", "6.7.8.9/10"]

        let configFetchResult = try await attemptRecoveryReturningConfigResult(with: lastServerName, newServerName: newServerName, lastAllowedIPs: lastAndNewAllowedIPs, newAllowedIPs: lastAndNewAllowedIPs)

        XCTAssertEqual(newServerName, configFetchResult?.tunnelConfig.name)
        XCTAssertEqual(newServerName, configFetchResult?.server.serverName)
    }

    func testAttemptRecovery_configUpdateFails_throwsError() async {
        do {
            try await attemptRecoveryWithConfigUpdateFailure()
            XCTFail("Expected error to be thrown")
        } catch {
            guard case FailureRecoveryError.reachedMaximumRetries(let lastError) = error else {
                XCTFail("Expected configGenerationError, got \(error)")
                return
            }
            guard case WireGuardAdapterError.startWireGuardBackend = lastError else {
                XCTFail("Expected underlying error to match stubbed")
                return
            }
        }
    }

    func testAttemptRecovery_allowedIPsDiffersFromPreviousAllowedIPs_returnsNewConfigAndServer() async throws {
        let lastAndNewServerName = "previousAndNewServerName"

        let configFetchResult = try? await attemptRecoveryReturningConfigResult(with: lastAndNewServerName, newServerName: lastAndNewServerName, lastAllowedIPs: ["1.2.3.4/5", "6.7.8.9/10"], newAllowedIPs: ["10.9.8.7/6", "5.4.3.2/1"])

        XCTAssertEqual(lastAndNewServerName, configFetchResult?.tunnelConfig.name)
        XCTAssertEqual(lastAndNewServerName, configFetchResult?.server.serverName)
    }

    func testAttemptRecovery_lastAndNewServerNamesAndAllowedIPsAreEqual_throwsNoRecoveryNecessaryError() async throws {
        do {
            try await attemptRecoveryWithLastAndNewServerNamesAndAllowedIPsEqual()
            XCTFail("Expected error to be thrown")
        } catch {
            guard case FailureRecoveryError.noRecoveryNecessary = error else {
                XCTFail("Expected noRecoveryNecessary, got \(error)")
                return
            }
        }
    }

    func testAttemptRecovery_sendsStartedEvent() async throws {
        var startedCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .started = step {
                    startedCount += 1
                }
            }
        )
        deviceManager.stubGenerateTunnelConfiguration = (
            tunnelConfig: .make(),
            server: .mockRegisteredServer
        )
        try? await failureRecoveryHandler.attemptRecovery(
            to: .mockRegisteredServer,
            includedRoutes: [],
            excludedRoutes: [],
            isKillSwitchEnabled: false
        ) {_ in }

        XCTAssertEqual(startedCount, 1)
    }

    func testAttemptRecovery_configGenerationFailure_sendsFailedEvent() async throws {
        var failedCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .failed = step {
                    failedCount += 1
                }
                if case .completed = step {
                    XCTFail("Expected no completed events")
                }
            }
        )

        try? await attemptRecoveryWithConfigGenerationFailure()

        XCTAssertEqual(failedCount, 1)
    }

    func testAttemptRecovery_configUpdateFailed_sendsFailedEvent() async throws {
        var failedCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .failed = step {
                    failedCount += 1
                }
                if case .completed = step {
                    XCTFail("Expected no completed events")
                }
            }
        )

        try? await attemptRecoveryWithConfigUpdateFailure()

        XCTAssertEqual(failedCount, 1)
    }

    func testAttemptRecovery_lastAndNewServerNamesAndAllowedIPsAreEqual_sendsHealthyCompletedEvent() async throws {
        var healthyCompleteCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .completed(.healthy) = step {
                    healthyCompleteCount += 1
                } else if case .failed = step {
                    XCTFail("Expected no failed events")
                }
            }
        )
        try? await attemptRecoveryWithLastAndNewServerNamesAndAllowedIPsEqual()

        XCTAssertEqual(healthyCompleteCount, 1)
    }

    func testAttemptRecovery_lastAndNewServerNamesAreDifferent_sendsUnhealthyCompletedEvent() async throws {
        var unhealthyCompleteCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .completed(.unhealthy) = step {
                    unhealthyCompleteCount += 1
                } else if case .failed = step {
                    XCTFail("Expected no failed events")
                }
            }
        )
        let lastServerName = "oldServerName"
        let newServerName = "newServerName"
        let lastAndNewAllowedIPs = ["1.2.3.4/5", "6.7.8.9/10"]

        _ = try? await attemptRecoveryReturningConfigResult(with: lastServerName, newServerName: newServerName, lastAllowedIPs: lastAndNewAllowedIPs, newAllowedIPs: lastAndNewAllowedIPs)

        XCTAssertEqual(unhealthyCompleteCount, 1)
    }

    func testAttemptRecovery_lastAndNewAllowedIPsAreDifferent_sendsUnhealthyCompletedEvent() async throws {
        let lastAndNewServerName = "previousAndNewServerName"

        var unhealthyCompleteCount = 0
        failureRecoveryHandler = FailureRecoveryHandler(
            deviceManager: deviceManager,
            retryConfig: Self.testConfig,
            eventHandler: { step in
                if case .completed(.unhealthy) = step {
                    unhealthyCompleteCount += 1
                } else if case .failed = step {
                    XCTFail("Expected no failed events")
                }
            }
        )

        _ = try? await attemptRecoveryReturningConfigResult(with: lastAndNewServerName, newServerName: lastAndNewServerName, lastAllowedIPs: ["1.2.3.4/5", "6.7.8.9/10"], newAllowedIPs: ["10.9.8.7/6", "5.4.3.2/1"])

        XCTAssertEqual(unhealthyCompleteCount, 1)
    }

    func attemptRecoveryWithLastAndNewServerNamesAndAllowedIPsEqual() async throws {
        let lastAndNewServerName = "previousAndNewServerName"
        let lastAndNewAllowedIPs = ["1.2.3.4/5", "10.9.8.7/6"]

        try await attemptRecoveryReturningConfigResult(with: lastAndNewServerName, newServerName: lastAndNewServerName, lastAllowedIPs: lastAndNewAllowedIPs, newAllowedIPs: lastAndNewAllowedIPs)
    }

    func attemptRecoveryWithConfigGenerationFailure() async throws {
        deviceManager.stubGenerateTunnelConfigurationError = NetworkProtectionError.noServerRegistrationInfo
        try? await failureRecoveryHandler.attemptRecovery(
            to: .mockRegisteredServer,
            includedRoutes: [],
            excludedRoutes: [],
            isKillSwitchEnabled: false
        ) {_ in }
    }

    func attemptRecoveryWithConfigUpdateFailure() async throws {
        let newServerName = "server2"
        let newServer = NetworkProtectionServer.registeredServer(named: newServerName, allowedIPs: ["1.2.3.4/5", "10.9.8.7/6"])

        deviceManager.stubGenerateTunnelConfiguration = (
            tunnelConfig: .make(named: newServerName),
            server: newServer
        )

        try await failureRecoveryHandler.attemptRecovery(
            to: .mockRegisteredServer,
            includedRoutes: [],
            excludedRoutes: [],
            isKillSwitchEnabled: false
        ) { _ in
            throw WireGuardAdapterError.startWireGuardBackend(0)
        }
    }

    @discardableResult
    func attemptRecoveryReturningConfigResult(with lastServerName: String, newServerName: String, lastAllowedIPs: [String], newAllowedIPs: [String]) async throws -> NetworkProtectionDeviceManagement.GenerateTunnelConfigResult? {
        let lastServer = NetworkProtectionServer.registeredServer(named: lastServerName, allowedIPs: lastAllowedIPs)
        let newServer = NetworkProtectionServer.registeredServer(named: newServerName, allowedIPs: newAllowedIPs)

        deviceManager.stubGenerateTunnelConfiguration = (
            tunnelConfig: .make(named: newServerName),
            server: newServer
        )

        var newConfigResult: NetworkProtectionDeviceManagement.GenerateTunnelConfigResult?

        try await failureRecoveryHandler.attemptRecovery(to: lastServer, includedRoutes: [], excludedRoutes: [], isKillSwitchEnabled: true) { configResult in
            newConfigResult = configResult
        }
        return newConfigResult
    }
}
