//
//  PacketTunnelProvider.swift
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

// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import Combine
import Common
import Foundation
import NetworkExtension
import UserNotifications

// swiftlint:disable file_length type_body_length line_length
open class PacketTunnelProvider: NEPacketTunnelProvider {

    public enum Event {
        case userBecameActive
        case reportLatency(ms: Int, server: String, networkType: NetworkConnectionType)
        case rekeyCompleted
    }

    // MARK: - Error Handling

    enum TunnelError: LocalizedError {
        case startingTunnelWithoutAuthToken
        case couldNotGenerateTunnelConfiguration(internalError: Error)
        case couldNotFixConnection
        case simulateTunnelFailureError

        var errorDescription: String? {
            switch self {
            case .startingTunnelWithoutAuthToken:
                return "Missing auth token at startup"
            case .couldNotGenerateTunnelConfiguration(let internalError):
                return "Failed to generate a tunnel configuration: \(internalError.localizedDescription)"
            case .simulateTunnelFailureError:
                return "Simulated a tunnel error as requested"
            default:
                // This is probably not the most elegant error to show to a user but
                // it's a great way to get detailed reports for those cases we haven't
                // provided good descriptions for yet.
                return "Tunnel error: \(String(describing: self))"
            }
        }
    }

    // MARK: - WireGuard

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { logLevel, message in
            if logLevel == .error {
                os_log("🔵 Received error from adapter: %{public}@", log: .networkProtection, type: .error, message)
            } else {
                os_log("🔵 Received message from adapter: %{public}@", log: .networkProtection, message)
            }
        }
    }()

    // MARK: - Timers Support

    private let timerQueue = DispatchQueue(label: "com.duckduckgo.network-protection.PacketTunnelProvider.timerQueue")

    // MARK: - Status

    public override var reasserting: Bool {
        get {
            super.reasserting
        }
        set {
            if newValue {
                connectionStatus = .reasserting
            } else {
                connectionStatus = .connected(connectedDate: Date())
            }

            super.reasserting = newValue
        }
    }

    public var connectionStatus: ConnectionStatus = .disconnected {
        didSet {
            guard connectionStatus != oldValue else {
                return
            }
            if case .connected = connectionStatus {
                self.notificationsPresenter.showConnectedNotification(serverLocation: lastSelectedServerInfo?.serverLocation)
            }
            connectionStatusPublisher.send(connectionStatus)
        }
    }

    public let connectionStatusPublisher = CurrentValueSubject<ConnectionStatus, Never>(.disconnected)

    public var isKillSwitchEnabled: Bool {
        guard #available(macOS 11.0, iOS 14.2, *) else { return false }
        return self.protocolConfiguration.enforceRoutes || self.protocolConfiguration.includeAllNetworks
    }

    // MARK: - Tunnel Settings

    private let settings = TunnelSettings(defaults: .standard)

    // MARK: - Server Selection

    public var lastSelectedServerInfo: NetworkProtectionServerInfo? {
        didSet {
            lastSelectedServerInfoPublisher.send(lastSelectedServerInfo)
        }
    }

    public let lastSelectedServerInfoPublisher = CurrentValueSubject<NetworkProtectionServerInfo?, Never>.init(nil)

    private var includedRoutes: [IPAddressRange]?
    private var excludedRoutes: [IPAddressRange]?

    // MARK: - User Notifications

    private let notificationsPresenter: NetworkProtectionNotificationsPresenter

    // MARK: - Registration Key

    private lazy var keyStore = NetworkProtectionKeychainKeyStore(keychainType: keychainType,
                                                                  errorEvents: debugEvents)

    private let tokenStore: NetworkProtectionTokenStore

    private func resetRegistrationKey() {
        os_log("Resetting the current registration key", log: .networkProtectionKeyManagement)
        keyStore.resetCurrentKeyPair()
    }

    private var isKeyExpired: Bool {
        keyStore.currentKeyPair().expirationDate <= Date()
    }

    private func rekeyIfExpired() async {
        guard isKeyExpired else {
            return
        }

        await rekey()
    }

    private func rekey() async {
        os_log("Rekeying...", log: .networkProtectionKeyManagement)

        providerEvents.fire(.userBecameActive)
        providerEvents.fire(.rekeyCompleted)

        self.resetRegistrationKey()

        do {
            try await updateTunnelConfiguration(selectedServer: settings.selectedServer, reassert: false)
        } catch {
            os_log("Rekey attempt failed.  This is not an error if you're using debug Key Management options: %{public}@", log: .networkProtectionKeyManagement, type: .error, String(describing: error))
        }
    }

    private func setKeyValidity(_ interval: TimeInterval?) {
        if let interval {
            let firstExpirationDate = Date().addingTimeInterval(interval)

            os_log("Setting key validity interval to %{public}@ seconds (next expiration date %{public}@)",
                   log: .networkProtectionKeyManagement,
                   String(describing: interval),
                   String(describing: firstExpirationDate))

            settings.registrationKeyValidity = .custom(interval)
        } else {
            os_log("Resetting key validity interval",
                   log: .networkProtectionKeyManagement)

            settings.registrationKeyValidity = .automatic
        }

        keyStore.setValidityInterval(interval)
    }

    // MARK: - Bandwidth Analyzer

    private func updateBandwidthAnalyzerAndRekeyIfExpired() {
        Task {
            await updateBandwidthAnalyzer()

            guard self.bandwidthAnalyzer.isConnectionIdle() else {
                return
            }

            await rekeyIfExpired()
        }
    }

    /// Updates the bandwidth analyzer with the latest data from the WireGuard Adapter
    ///
    public func updateBandwidthAnalyzer() async {
        guard let (rx, tx) = try? await adapter.getBytesTransmitted() else {
            self.bandwidthAnalyzer.preventIdle()
            return
        }

        bandwidthAnalyzer.record(rxBytes: rx, txBytes: tx)
    }

    // MARK: - Connection tester

    private var isConnectionTesterEnabled: Bool = true

    private lazy var connectionTester: NetworkProtectionConnectionTester = {
        NetworkProtectionConnectionTester(timerQueue: timerQueue, log: .networkProtectionConnectionTesterLog) { @MainActor [weak self] (result, isStartupTest) in
            guard let self else { return }

            switch result {
            case .connected:
                self.tunnelHealth.isHavingConnectivityIssues = false
                self.updateBandwidthAnalyzerAndRekeyIfExpired()
                self.startLatencyReporter()

            case .reconnected:
                self.tunnelHealth.isHavingConnectivityIssues = false
                self.updateBandwidthAnalyzerAndRekeyIfExpired()
                self.startLatencyReporter()

            case .disconnected(let failureCount):
                self.tunnelHealth.isHavingConnectivityIssues = true
                self.bandwidthAnalyzer.reset()
                self.latencyReporter.stop()

                if failureCount == 1 {
                    self.notificationsPresenter.showReconnectingNotification()

                    // Only do these things if this is not a connection startup test.
                    if !isStartupTest {
                        self.fixTunnel()
                    }
                } else if failureCount == 2 {
                    self.stopTunnel(with: TunnelError.couldNotFixConnection)
                }
            }
        }
    }()

    @MainActor
    private func startLatencyReporter() {
        guard let lastSelectedServerInfo,
              let ip = lastSelectedServerInfo.ipv4 else {
            assertionFailure("could not get server IPv4 address")
            self.latencyReporter.stop()
            return
        }
        if self.latencyReporter.isStarted {
            if self.latencyReporter.currentIP == ip {
                return
            }
            self.latencyReporter.stop()
        }

        self.latencyReporter.start(ip: ip) { [serverName=lastSelectedServerInfo.name, providerEvents] latency, networkType in
            providerEvents.fire(.reportLatency(ms: Int(latency * 1000), server: serverName, networkType: networkType))
        }
    }

    private var lastTestFailed = false
    private let bandwidthAnalyzer = NetworkProtectionConnectionBandwidthAnalyzer()
    private let tunnelHealth: NetworkProtectionTunnelHealthStore
    private let controllerErrorStore: NetworkProtectionTunnelErrorStore
    private let latencyReporter = NetworkProtectionLatencyReporter(log: .networkProtection)

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializers

    private let keychainType: KeychainType
    private let debugEvents: EventMapping<NetworkProtectionError>?
    private let providerEvents: EventMapping<Event>

    public init(notificationsPresenter: NetworkProtectionNotificationsPresenter,
                tunnelHealthStore: NetworkProtectionTunnelHealthStore,
                controllerErrorStore: NetworkProtectionTunnelErrorStore,
                keychainType: KeychainType,
                tokenStore: NetworkProtectionTokenStore,
                debugEvents: EventMapping<NetworkProtectionError>?,
                providerEvents: EventMapping<Event>) {
        os_log("[+] PacketTunnelProvider", log: .networkProtectionMemoryLog, type: .debug)

        self.notificationsPresenter = notificationsPresenter
        self.keychainType = keychainType
        self.tokenStore = tokenStore
        self.debugEvents = debugEvents
        self.providerEvents = providerEvents
        self.tunnelHealth = tunnelHealthStore
        self.controllerErrorStore = controllerErrorStore

        super.init()
    }

    deinit {
        os_log("[-] PacketTunnelProvider", log: .networkProtectionMemoryLog, type: .debug)
    }

    private var tunnelProviderProtocol: NETunnelProviderProtocol? {
        protocolConfiguration as? NETunnelProviderProtocol
    }

    private func runDebugSimulations(options: StartupOptions) throws {
        if options.simulateError {
            throw TunnelError.simulateTunnelFailureError
        }

        if options.simulateCrash {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval.seconds(2)) {
                fatalError("Simulated PacketTunnelProvider crash")
            }

            return
        }

        if options.simulateMemoryCrash {
            Task {
                var array = [String]()
                while true {
                    array.append("Crash")
                }
            }

            return
        }
    }

    private func load(options: StartupOptions) throws {
        loadKeyValidity(from: options)
        loadSelectedServer(from: options)
        loadTesterEnabled(from: options)
        try loadAuthToken(from: options)
    }

    open func loadVendorOptions(from provider: NETunnelProviderProtocol?) throws {
        let vendorOptions = provider?.providerConfiguration

        loadRoutes(from: vendorOptions)
    }

    private func loadKeyValidity(from options: StartupOptions) {
        switch options.keyValidity {
        case .set(let validity):
            setKeyValidity(validity)
        case .useExisting:
            break
        case .reset:
            setKeyValidity(nil)
        }
    }

    private func loadSelectedServer(from options: StartupOptions) {
        switch options.selectedServer {
        case .set(let selectedServer):
            settings.selectedServer = selectedServer
        case .useExisting:
            break
        case .reset:
            settings.selectedServer = .automatic
        }
    }

    private func loadTesterEnabled(from options: StartupOptions) {
        switch options.enableTester {
        case .set(let value):
            isConnectionTesterEnabled = value
        case .useExisting:
            break
        case .reset:
            isConnectionTesterEnabled = true
        }
    }

    private func loadAuthToken(from options: StartupOptions) throws {
        switch options.authToken {
        case .set(let authToken):
            try tokenStore.store(authToken)
        case .useExisting:
            break
        case .reset:
            // This case should in theory not be possible, but it's ideal to have this in place
            // in case an error in the controller on the client side allows it.
            try tokenStore.deleteToken()
            throw TunnelError.startingTunnelWithoutAuthToken
        }
    }

    private func loadRoutes(from options: [String: Any]?) {
        self.includedRoutes = (options?[NetworkProtectionOptionKey.includedRoutes] as? [String])?.compactMap(IPAddressRange.init(from:)) ?? []

        self.excludedRoutes = (options?[NetworkProtectionOptionKey.excludedRoutes] as? [String])?.compactMap(IPAddressRange.init(from:))
        ?? [ // fallback to default local network exclusions
            "10.0.0.0/8",     // 255.0.0.0
            "172.16.0.0/12",  // 255.240.0.0
            "192.168.0.0/16", // 255.255.0.0
            "169.254.0.0/16", // 255.255.0.0 : Link-local
            "127.0.0.0/8",    // 255.0.0.0 : Loopback
            "224.0.0.0/4",    // 240.0.0.0 : Multicast
            "100.64.0.0/16",  // 255.255.0.0 : Shared Address Space
        ]
    }

    // MARK: - Tunnel Start

    open override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        connectionStatus = .connecting

        os_log("Will load options\n%{public}@", log: .networkProtection, String(describing: options))
        let startupOptions = StartupOptions(options: options ?? [:], log: .networkProtection)

        resetIssueStateOnTunnelStart(startupOptions)

        let startTime = DispatchTime.now()

        let internalCompletionHandler = { [weak self] (error: Error?) in
            guard let self else {
                completionHandler(error)
                return
            }

            guard let error else {
                completionHandler(nil)
                return
            }

            let handler = {
                let errorDescription = (error as? LocalizedError)?.localizedDescription ?? String(describing: error)

                os_log("Tunnel startup error: %{public}@", type: .error, errorDescription)
                self.controllerErrorStore.lastErrorMessage = errorDescription
                self.connectionStatus = .disconnected

                completionHandler(error)
            }

            if startupOptions.startupMethod == .automaticOnDemand {
                DispatchQueue.main.asyncAfter(deadline: startTime + DispatchTimeInterval.seconds(10), execute: handler)
            } else {
                handler()
            }
        }

        startTunnel(options: startupOptions, completionHandler: internalCompletionHandler)
    }

    private func startTunnel(options: StartupOptions, completionHandler: @escaping (Error?) -> Void) {
        do {
            try runDebugSimulations(options: options)
            try load(options: options)
            try loadVendorOptions(from: tunnelProviderProtocol)
        } catch {
            completionHandler(error)
            return
        }

        let onDemand = options.startupMethod == .automaticOnDemand

        os_log("Starting tunnel %{public}@", log: .networkProtection, options.startupMethod.debugDescription)
        startTunnel(selectedServer: settings.selectedServer, onDemand: onDemand, completionHandler: completionHandler)
    }

    private func startTunnel(selectedServer: TunnelSettings.SelectedServer, onDemand: Bool, completionHandler: @escaping (Error?) -> Void) {

        Task {
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            switch settings.selectedServer {
            case .automatic:
                serverSelectionMethod = .automatic
            case .endpoint(let serverName):
                serverSelectionMethod = .preferredServer(serverName: serverName)
            }

            do {
                os_log("🔵 Generating tunnel config", log: .networkProtection, type: .info)
                let tunnelConfiguration = try await generateTunnelConfiguration(serverSelectionMethod: serverSelectionMethod,
                                                                                includedRoutes: includedRoutes ?? [],
                                                                                excludedRoutes: excludedRoutes ?? [])
                startTunnel(with: tunnelConfiguration, onDemand: onDemand, completionHandler: completionHandler)
                os_log("🔵 Done generating tunnel config", log: .networkProtection, type: .info)
            } catch {
                os_log("🔵 Error starting tunnel: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)

                controllerErrorStore.lastErrorMessage = error.localizedDescription

                completionHandler(error)
            }
        }
    }

    private func startTunnel(with tunnelConfiguration: TunnelConfiguration, onDemand: Bool, completionHandler: @escaping (Error?) -> Void) {
        
        adapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] error in
            if let error {
                os_log("🔵 Starting tunnel failed with %{public}@", log: .networkProtection, type: .error, error.localizedDescription)
                self?.debugEvents?.fire(error.networkProtectionError)
                completionHandler(error)
                return
            }

            Task { [weak self] in
                // It's important to call this completion handler before running the tester
                // as if we don't, the tester will just fail.  It seems like the connection
                // won't fully work until the completion handler is called.
                completionHandler(nil)

                do {
                    let startReason: AdapterStartReason = onDemand ? .onDemand : .manual
                    try await self?.handleAdapterStarted(startReason: startReason)
                } catch {
                    self?.cancelTunnelWithError(error)
                    return
                }
            }
        }
    }

    // MARK: - Tunnel Stop

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        connectionStatus = .disconnecting
        os_log("Stopping tunnel with reason %{public}@", log: .networkProtection, type: .info, String(describing: reason))

        adapter.stop { [weak self] error in
            if let error {
                os_log("🔵 Failed to stop WireGuard adapter: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)
                self?.debugEvents?.fire(error.networkProtectionError)
            }

            Task { [weak self] in
                await self?.handleAdapterStopped()
                if case .superceded = reason {
                    self?.notificationsPresenter.showSupersededNotification()
                }

                completionHandler()
            }
        }
    }

    /// Do not cancel, directly... call this method so that the adapter and tester are stopped too.
    private func stopTunnel(with stopError: Error) {
        connectionStatus = .disconnecting

        os_log("Stopping tunnel with error %{public}@", log: .networkProtection, type: .info, stopError.localizedDescription)

        Task {
            await handleAdapterStopped()
        }

        self.adapter.stop { [weak self] error in
            if let error = error {
                os_log("Error while stopping adapter: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)
                self?.debugEvents?.fire(error.networkProtectionError)
            }

            self?.cancelTunnelWithError(stopError)
        }
    }

    // MARK: - Fix Issues Management

    /// Resets the issue state when startup up the tunnel manually.
    ///
    /// When the tunnel is started by on-demand the issue state should not be cleared until the tester
    /// reports a working connection.
    ///
    private func resetIssueStateOnTunnelStart(_ startupOptions: StartupOptions) {
        guard startupOptions.startupMethod != .automaticOnDemand else {
            return
        }

        tunnelHealth.isHavingConnectivityIssues = false
        controllerErrorStore.lastErrorMessage = nil
    }

    /// Intentionally not async, so that we won't lock whoever called this method.  This method will race against the tester
    /// to see if it can fix the connection before the next failure.
    ///
    private func fixTunnel() {
        Task {
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            if let lastServerName = lastSelectedServerInfo?.name {
                serverSelectionMethod = .avoidServer(serverName: lastServerName)
            } else {
                assertionFailure("We should not have a situation where the VPN is trying to fix the tunnel and there's no previous server info")
                serverSelectionMethod = .automatic
            }

            do {
                try await updateTunnelConfiguration(serverSelectionMethod: serverSelectionMethod)
            } catch {
                return
            }
        }
    }

    // MARK: - Tunnel Configuration

    public func updateTunnelConfiguration(selectedServer: TunnelSettings.SelectedServer, reassert: Bool = true) async throws {
        let serverSelectionMethod: NetworkProtectionServerSelectionMethod

        switch settings.selectedServer {
        case .automatic:
            serverSelectionMethod = .automatic
        case .endpoint(let serverName):
            serverSelectionMethod = .preferredServer(serverName: serverName)
        }

        try await updateTunnelConfiguration(serverSelectionMethod: serverSelectionMethod, reassert: reassert)
    }

    public func updateTunnelConfiguration(serverSelectionMethod: NetworkProtectionServerSelectionMethod, reassert: Bool = true) async throws {

        let tunnelConfiguration = try await generateTunnelConfiguration(serverSelectionMethod: serverSelectionMethod,
                                                                        includedRoutes: includedRoutes ?? [],
                                                                        excludedRoutes: excludedRoutes ?? [])

        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self = self else {
                continuation.resume()
                return
            }

            self.adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: reassert) { [weak self] error in
                if let error = error {
                    os_log("🔵 Failed to update the configuration: %{public}@", type: .error, error.localizedDescription)
                    self?.debugEvents?.fire(error.networkProtectionError)
                    continuation.resume(throwing: error)
                    return
                }

                Task { [weak self] in
                    do {
                        try await self?.handleAdapterStarted(startReason: .reconnected)
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume()
                }
            }
        }
    }

    private func generateTunnelConfiguration(serverSelectionMethod: NetworkProtectionServerSelectionMethod, includedRoutes: [IPAddressRange], excludedRoutes: [IPAddressRange]) async throws -> TunnelConfiguration {

        let configurationResult: (TunnelConfiguration, NetworkProtectionServerInfo)

        do {
            let deviceManager = NetworkProtectionDeviceManager(tokenStore: tokenStore,
                                                               keyStore: keyStore,
                                                               errorEvents: debugEvents)

            configurationResult = try await deviceManager.generateTunnelConfiguration(selectionMethod: serverSelectionMethod, includedRoutes: includedRoutes, excludedRoutes: excludedRoutes, isKillSwitchEnabled: isKillSwitchEnabled)
        } catch {
            throw TunnelError.couldNotGenerateTunnelConfiguration(internalError: error)
        }

        let selectedServerInfo = configurationResult.1
        self.lastSelectedServerInfo = selectedServerInfo

        os_log("🔵 Generated tunnel configuration for server at location: %{public}s (preferred server is %{public}s)",
               log: .networkProtection,
               selectedServerInfo.serverLocation,
               selectedServerInfo.name)

        let tunnelConfiguration = configurationResult.0

        return tunnelConfiguration
    }

    // MARK: - App Messages

    // swiftlint:disable:next cyclomatic_complexity
    public override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let message = ExtensionMessage(rawValue: messageData) else {
            completionHandler?(nil)
            return
        }

        switch message {
        case .request(let request):
            handleRequest(request)
        case .expireRegistrationKey:
            handleExpireRegistrationKey(completionHandler: completionHandler)
        case .getLastErrorMessage:
            handleGetLastErrorMessage(completionHandler: completionHandler)
        case .getRuntimeConfiguration:
            handleGetRuntimeConfiguration(completionHandler: completionHandler)
        case .isHavingConnectivityIssues:
            handleIsHavingConnectivityIssues(completionHandler: completionHandler)
        case .setSelectedServer(let serverName):
            handleSetSelectedServer(serverName, completionHandler: completionHandler)
        case .getServerLocation:
            handleGetServerLocation(completionHandler: completionHandler)
        case .getServerAddress:
            handleGetServerAddress(completionHandler: completionHandler)
        case .setKeyValidity(let keyValidity):
            handleSetKeyValidity(keyValidity, completionHandler: completionHandler)
        case .resetAllState:
            handleResetAllState(completionHandler: completionHandler)
        case .triggerTestNotification:
            handleSendTestNotification(completionHandler: completionHandler)
        case .setExcludedRoutes(let excludedRoutes):
            setExcludedRoutes(excludedRoutes, completionHandler: completionHandler)
        case .setIncludedRoutes(let includedRoutes):
            setIncludedRoutes(includedRoutes, completionHandler: completionHandler)
        case .simulateTunnelFailure:
            simulateTunnelFailure(completionHandler: completionHandler)
        case .simulateTunnelFatalError:
            simulateTunnelFatalError(completionHandler: completionHandler)
        case .simulateTunnelMemoryOveruse:
            simulateTunnelMemoryOveruse(completionHandler: completionHandler)
        case .simulateConnectionInterruption:
            simulateConnectionInterruption(completionHandler: completionHandler)
        }
    }

    // MARK: - App Requests: Handling

    private func handleRequest(_ request: ExtensionRequest, completionHandler: ((Data?) -> Void)? = nil) {
        switch request {
        case .changeTunnelSetting(let change):
            handleSettingsChange(change, completionHandler: completionHandler)
        case .debugCommand(let command):
            handleDebugCommand(command, completionHandler: completionHandler)
        }
    }

    private func handleSettingsChange(_ change: TunnelSettings.Change, completionHandler: ((Data?) -> Void)? = nil) {

        settings.apply(change: change)

        switch change {
        case .setSelectedServer(let selectedServer):
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            switch selectedServer {
            case .automatic:
                serverSelectionMethod = .automatic
            case .endpoint(let serverName):
                serverSelectionMethod = .preferredServer(serverName: serverName)
            }

            Task {
                try? await updateTunnelConfiguration(serverSelectionMethod: serverSelectionMethod)
                completionHandler?(nil)
            }
        case .setIncludeAllNetworks,
                .setEnforceRoutes,
                .setExcludeLocalNetworks,
                .setRegistrationKeyValidity:
            // Intentional no-op, as some setting changes don't require any further operation
            break
        }
    }

    private func handleDebugCommand(_ command: DebugCommand, completionHandler: ((Data?) -> Void)? = nil) {
        switch command {
        case .deactivateSystemExtension:
            // Intentional no-op: handled by the VPN agent
            break
        case .expireRegistrationKey:
            handleExpireRegistrationKey(completionHandler: completionHandler)
        case .sendTestNotification:
            handleSendTestNotification(completionHandler: completionHandler)
        case .removeVPNConfiguration:
            // Intentional no-op: handled by the VPN agent
            break
        }
    }

    // MARK: - App Messages: Handling

    private func handleExpireRegistrationKey(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            await rekey()
            completionHandler?(nil)
        }
    }

    private func handleResetAllState(completionHandler: ((Data?) -> Void)? = nil) {
        resetRegistrationKey()

        let serverCache = NetworkProtectionServerListFileSystemStore(errorEvents: nil)
        try? serverCache.removeServerList()

        try? tokenStore.deleteToken()

        // This is not really an error, we received a command to reset the connection
        cancelTunnelWithError(nil)
        completionHandler?(nil)
    }

    private func handleGetLastErrorMessage(completionHandler: ((Data?) -> Void)? = nil) {
        let response = controllerErrorStore.lastErrorMessage.map(ExtensionMessageString.init)
        completionHandler?(response?.rawValue)
    }

    private func handleGetRuntimeConfiguration(completionHandler: ((Data?) -> Void)? = nil) {
        adapter.getRuntimeConfiguration { settings in
            let response = settings.map(ExtensionMessageString.init)
            completionHandler?(response?.rawValue)
        }
    }

    private func handleIsHavingConnectivityIssues(completionHandler: ((Data?) -> Void)? = nil) {
        let response = ExtensionMessageBool(tunnelHealth.isHavingConnectivityIssues)
        completionHandler?(response.rawValue)
    }

    private func handleSetSelectedServer(_ serverName: String?, completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            guard let serverName else {
                if case .endpoint = settings.selectedServer {
                    settings.selectedServer = .automatic
                    try? await updateTunnelConfiguration(serverSelectionMethod: .automatic)
                }
                completionHandler?(nil)
                return
            }

            guard settings.selectedServer.stringValue != serverName else {
                completionHandler?(nil)
                return
            }

            settings.selectedServer = .endpoint(serverName)
            try? await updateTunnelConfiguration(serverSelectionMethod: .preferredServer(serverName: serverName))
            completionHandler?(nil)
        }
    }

    private func handleGetServerLocation(completionHandler: ((Data?) -> Void)? = nil) {
        let response = lastSelectedServerInfo.map { ExtensionMessageString($0.serverLocation) }
        completionHandler?(response?.rawValue)
    }

    private func handleGetServerAddress(completionHandler: ((Data?) -> Void)? = nil) {
        let response = lastSelectedServerInfo?.endpoint.map { ExtensionMessageString($0.description) }
        completionHandler?(response?.rawValue)
    }

    private func handleSetKeyValidity(_ keyValidity: TimeInterval?, completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            setKeyValidity(keyValidity)
            completionHandler?(nil)
        }
    }

    private func handleSendTestNotification(completionHandler: ((Data?) -> Void)? = nil) {
        notificationsPresenter.showTestNotification()
        completionHandler?(nil)
    }

    private func setExcludedRoutes(_ excludedRoutes: [IPAddressRange], completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            self.excludedRoutes = excludedRoutes
            try? await updateTunnelConfiguration(selectedServer: settings.selectedServer, reassert: false)
            completionHandler?(nil)
        }
    }

    private func setIncludedRoutes(_ includedRoutes: [IPAddressRange], completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            self.includedRoutes = includedRoutes
            try? await updateTunnelConfiguration(selectedServer: settings.selectedServer, reassert: false)
            completionHandler?(nil)
        }
    }

    private func simulateTunnelFailure(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            os_log("Simulating tunnel failure", log: .networkProtection, type: .info)

            adapter.stop { [weak self] error in
                if let error {
                    self?.debugEvents?.fire(error.networkProtectionError)
                    os_log("🔵 Failed to stop WireGuard adapter: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)
                }

                completionHandler?(error.map { ExtensionMessageString($0.localizedDescription).rawValue })
            }
        }
    }

    private func simulateTunnelFatalError(completionHandler: ((Data?) -> Void)? = nil) {
        completionHandler?(nil)
        fatalError("Simulated PacketTunnelProvider crash")
    }

    private func simulateTunnelMemoryOveruse(completionHandler: ((Data?) -> Void)? = nil) {
        completionHandler?(nil)
        var array = [String]()
        while true {
            array.append("Crash")
        }
    }

    private func simulateConnectionInterruption(completionHandler: ((Data?) -> Void)? = nil) {
        connectionTester.failNextTest()
        completionHandler?(nil)
    }

    // MARK: - Adapter start completion handling

    private enum AdapterStartReason {
        case manual
        case onDemand
        case reconnected
        case wake
    }

    /// Called when the adapter reports that the tunnel was successfully started.
    ///
    private func handleAdapterStarted(startReason: AdapterStartReason) async throws {
        if startReason != .reconnected && startReason != .wake {
            connectionStatus = .connected(connectedDate: Date())
        }

        guard !isKeyExpired else {
            await rekey()
            return
        }

        os_log("🔵 Tunnel interface is %{public}@", log: .networkProtection, type: .info, adapter.interfaceName ?? "unknown")

        do {
            // These cases only make sense in the context of a connection that had trouble
            // and is being fixed, so we want to test the connection immediately.
            let testImmediately = startReason == .reconnected || startReason == .onDemand

            try await startConnectionTester(testImmediately: testImmediately)
        } catch {
            os_log("🔵 Connection Tester error: %{public}@", log: .networkProtectionConnectionTesterLog, type: .error, String(reflecting: error))
            throw error
        }
    }

    public func handleAdapterStopped() async {
        connectionStatus = .disconnected
        await self.connectionTester.stop()
    }

    // MARK: - Connection Tester

    private enum ConnectionTesterError: Error {
        case couldNotRetrieveInterfaceNameFromAdapter
        case testerFailedToStart(internalError: Error)
    }

    private func startConnectionTester(testImmediately: Bool) async throws {
        guard isConnectionTesterEnabled else {
            os_log("The connection tester is disabled", log: .networkProtectionConnectionTesterLog)
            return
        }

        guard let interfaceName = adapter.interfaceName else {
            throw ConnectionTesterError.couldNotRetrieveInterfaceNameFromAdapter
        }

        do {
            try await connectionTester.start(tunnelIfName: interfaceName, testImmediately: testImmediately)
        } catch {
            switch error {
            case NetworkProtectionConnectionTester.TesterError.couldNotFindInterface:
                os_log("Printing current proposed utun: %{public}@", log: .networkProtectionConnectionTesterLog, String(reflecting: adapter.interfaceName))
            default:
                break
            }

            throw ConnectionTesterError.testerFailedToStart(internalError: error)
        }
    }

    // MARK: - Computer sleeping

    public override func sleep() async {
        os_log("Sleep", log: .networkProtectionSleepLog, type: .info)

        await connectionTester.stop()
    }

    public override func wake() {
        os_log("Wake up", log: .networkProtectionSleepLog, type: .info)

        Task {
            try? await handleAdapterStarted(startReason: .wake)
        }
    }
}

extension WireGuardAdapterError: LocalizedError, CustomDebugStringConvertible {

    public var errorDescription: String? {
        switch self {
        case .cannotLocateTunnelFileDescriptor:
            return "Starting tunnel failed: could not determine file descriptor"

        case .dnsResolution(let dnsErrors):
            let hostnamesWithDnsResolutionFailure = dnsErrors.map { $0.address }
                .joined(separator: ", ")
            return "DNS resolution failed for the following hostnames: \(hostnamesWithDnsResolutionFailure)"

        case .setNetworkSettings(let error):
            return "Starting tunnel failed with setTunnelNetworkSettings returning: \(error.localizedDescription)"

        case .startWireGuardBackend(let errorCode):
            return "Starting tunnel failed with wgTurnOn returning: \(errorCode)"

        case .invalidState:
            return "Starting tunnel failed with invalid error"
        }
    }

    public var debugDescription: String {
        errorDescription!
    }

}
// swiftlint:enable file_length type_body_length line_length
