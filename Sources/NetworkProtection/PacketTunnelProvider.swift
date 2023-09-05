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
        case couldNotGenerateTunnelConfiguration(internalError: Error)
        case couldNotFixConnection
        case simulateTunnelFailureError

        var errorDescription: String? {
            switch self {
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

            connectionStatusPublisher.send(connectionStatus)
        }
    }

    public let connectionStatusPublisher = CurrentValueSubject<ConnectionStatus, Never>(.disconnected)

    public var isKillSwitchEnabled: Bool {
        guard #available(macOS 11.0, iOS 14.2, *) else { return false }
        return self.protocolConfiguration.enforceRoutes || self.protocolConfiguration.includeAllNetworks
    }

    // MARK: - Server Selection

    let selectedServerStore = NetworkProtectionSelectedServerUserDefaultsStore()

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

    private lazy var tokenStore = NetworkProtectionKeychainTokenStore(keychainType: keychainType,
                                                                      errorEvents: debugEvents)

    /// This is for overriding the defaults.  A `nil` value means NetP will just use the defaults.
    ///
    private var keyValidity: TimeInterval?

    private static let defaultRetryInterval: TimeInterval = .minutes(1)

    /// Normally we'll retry using the default interval, but since we can override the key validity interval for testing purposes
    /// we'll retry sooner if it's been overridden with values lower than the default retry interval.
    ///
    /// In practical terms this means that if the validity interval is 15 secs, the retry will also be 15 secs instead of 1 minute.
    ///
    private var retryInterval: TimeInterval {
        guard let keyValidity = keyValidity else {
            return Self.defaultRetryInterval
        }

        return keyValidity > Self.defaultRetryInterval ? Self.defaultRetryInterval : keyValidity
    }

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
            try await updateTunnelConfiguration(selectedServer: selectedServerStore.selectedServer, reassert: false)
        } catch {
            os_log("Rekey attempt failed.  This is not an error if you're using debug Key Management options: %{public}@", log: .networkProtectionKeyManagement, type: .error, String(describing: error))
        }
    }

    private func setKeyValidity(_ interval: TimeInterval?) {
        guard keyValidity != interval,
            let interval = interval else {

            return
        }

        let firstExpirationDate = Date().addingTimeInterval(interval)

        os_log("Setting key validity to %{public}@ seconds (next expiration date %{public}@)",
               log: .networkProtectionKeyManagement,
               type: .info,
               String(describing: interval),
               String(describing: firstExpirationDate))
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
        NetworkProtectionConnectionTester(timerQueue: timerQueue, log: .networkProtectionConnectionTesterLog) { @MainActor [weak self] result in
            guard let self else { return }

            switch result {
            case .connected:
                self.tunnelHealth.isHavingConnectivityIssues = false
                self.updateBandwidthAnalyzerAndRekeyIfExpired()
                self.startLatencyReporter()

            case .reconnected:
                self.tunnelHealth.isHavingConnectivityIssues = false
                self.notificationsPresenter.showReconnectedNotification()
                self.reasserting = false
                self.updateBandwidthAnalyzerAndRekeyIfExpired()
                self.startLatencyReporter()

            case .disconnected(let failureCount):
                self.tunnelHealth.isHavingConnectivityIssues = true
                self.bandwidthAnalyzer.reset()
                self.latencyReporter.stop()

                if failureCount == 1 {
                    self.notificationsPresenter.showReconnectingNotification()
                    self.reasserting = true
                    self.fixTunnel()
                } else if failureCount == 2 {
                    self.notificationsPresenter.showConnectionFailureNotification()
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
                debugEvents: EventMapping<NetworkProtectionError>?,
                providerEvents: EventMapping<Event>) {
        os_log("[+] PacketTunnelProvider", log: .networkProtectionMemoryLog, type: .debug)

        self.notificationsPresenter = notificationsPresenter
        self.keychainType = keychainType
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

    private func load(options: [String: NSObject]?) throws {
        guard let options = options else {
            os_log("🔵 Tunnel options are not set", log: .networkProtection)
            return
        }

        loadKeyValidity(from: options)
        loadSelectedServer(from: options)
        try loadAuthToken(from: options)
    }

    open func loadVendorOptions(from provider: NETunnelProviderProtocol?) throws {
        let vendorOptions = provider?.providerConfiguration

        loadRoutes(from: vendorOptions)
        self.isConnectionTesterEnabled = vendorOptions?[NetworkProtectionOptionKey.connectionTesterEnabled] as? Bool ?? true
    }

    private func loadKeyValidity(from options: [String: AnyObject]) {
        guard let keyValidityString = options[NetworkProtectionOptionKey.keyValidity] as? String,
              let keyValidity = TimeInterval(keyValidityString) else {
            return
        }

        setKeyValidity(keyValidity)
    }

    private func loadSelectedServer(from options: [String: AnyObject]) {
        guard let serverName = options[NetworkProtectionOptionKey.selectedServer] as? String else {
            return
        }

        selectedServerStore.selectedServer = .endpoint(serverName)
    }

    private func loadAuthToken(from options: [String: AnyObject]) throws {
        guard let authToken = options[NetworkProtectionOptionKey.authToken] as? String else {
            return
        }

        try tokenStore.store(authToken)
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

        // when activated by system "on-demand" the option is set
        var isOnDemand: Bool {
            options?[NetworkProtectionOptionKey.isOnDemand] as? Bool == true
        }
        var isActivatedFromSystemSettings: Bool {
            options?[NetworkProtectionOptionKey.activationAttemptId] == nil && !isOnDemand
        }

        let internalCompletionHandler = { [weak self] (error: Error?) in
            if error != nil {
                self?.connectionStatus = .disconnected
                completionHandler(error)
                return
            }

            completionHandler(nil)
        }

        tunnelHealth.isHavingConnectivityIssues = false
        controllerErrorStore.lastErrorMessage = nil

        os_log("🔵 Will load options\n%{public}@", log: .networkProtection, String(describing: options))

        if options?[NetworkProtectionOptionKey.tunnelFailureSimulation] == NetworkProtectionOptionValue.true {
            internalCompletionHandler(TunnelError.simulateTunnelFailureError)
            controllerErrorStore.lastErrorMessage = TunnelError.simulateTunnelFailureError.localizedDescription
            return
        }

        if options?[NetworkProtectionOptionKey.tunnelFatalErrorCrashSimulation] == NetworkProtectionOptionValue.true {
            fatalError("Simulater Tunnel Fatal Error")
        }

        if options?[NetworkProtectionOptionKey.tunnelMemoryCrashSimulation] == NetworkProtectionOptionValue.true {
            var array = [String]()
            while true {
                array.append("crash")
            }
        }

        do {
            try load(options: options)
            try loadVendorOptions(from: tunnelProviderProtocol)
        } catch {
            internalCompletionHandler(error)
            return
        }

        os_log("🔵 Done! Starting tunnel from the %{public}@", log: .networkProtection, type: .info, (isActivatedFromSystemSettings ? "settings" : (isOnDemand ? "on-demand" : "app")))

        startTunnel(selectedServer: selectedServerStore.selectedServer, completionHandler: internalCompletionHandler)
    }

    private func startTunnel(selectedServer: SelectedNetworkProtectionServer, completionHandler: @escaping (Error?) -> Void) {

        Task {
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            switch selectedServerStore.selectedServer {
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
                startTunnel(with: tunnelConfiguration, completionHandler: completionHandler)
                os_log("🔵 Done generating tunnel config", log: .networkProtection, type: .info)
            } catch {
                os_log("🔵 Error starting tunnel: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)

                controllerErrorStore.lastErrorMessage = error.localizedDescription

                completionHandler(error)
            }
        }
    }

    private func startTunnel(with tunnelConfiguration: TunnelConfiguration, completionHandler: @escaping (Error?) -> Void) {
        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            if let error {
                os_log("🔵 Starting tunnel failed with %{public}@", log: .networkProtection, type: .error, error.localizedDescription)
                completionHandler(error)
                return
            }

            Task {
                await self.handleAdapterStarted()
                completionHandler(nil)
            }
        }
    }

    // MARK: - Tunnel Stop

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        connectionStatus = .disconnecting
        os_log("Stopping tunnel with reason %{public}@", log: .networkProtection, type: .info, String(describing: reason))

        adapter.stop { error in
            if let error {
                os_log("🔵 Failed to stop WireGuard adapter: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)
            }

            Task {
                await self.handleAdapterStopped()
                if case .superceded = reason {
                    self.notificationsPresenter.showSupersededNotification()
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

        self.adapter.stop { error in
            if let error = error {
                os_log("Error while stopping adapter: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)
            }

            self.cancelTunnelWithError(stopError)
        }
    }

    // MARK: - Fix Tunnel

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

    public func updateTunnelConfiguration(selectedServer: SelectedNetworkProtectionServer, reassert: Bool = true) async throws {
        let serverSelectionMethod: NetworkProtectionServerSelectionMethod

        switch selectedServerStore.selectedServer {
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

            self.adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: reassert) { error in
                if let error = error {
                    os_log("🔵 Failed to update the configuration: %{public}@", type: .error, error.localizedDescription)
                    continuation.resume(throwing: error)
                    return
                }

                Task {
                    await self.handleAdapterStarted(resumed: false)
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
            handleTriggerTestNotification(completionHandler: completionHandler)
        case .setExcludedRoutes(let excludedRoutes):
            setExcludedRoutes(excludedRoutes, completionHandler: completionHandler)
        case .setIncludedRoutes(let includedRoutes):
            setIncludedRoutes(includedRoutes, completionHandler: completionHandler)
        case .simulateTunnelFailure:
            simulateTunnelFailure(completionHandler: completionHandler)
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

                if case .endpoint = selectedServerStore.selectedServer {
                    selectedServerStore.selectedServer = .automatic
                    try? await updateTunnelConfiguration(serverSelectionMethod: .automatic)
                }
                completionHandler?(nil)
                return
            }

            guard selectedServerStore.selectedServer.stringValue != serverName else {
                completionHandler?(nil)
                return
            }

            selectedServerStore.selectedServer = .endpoint(serverName)
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

    private func handleTriggerTestNotification(completionHandler: ((Data?) -> Void)? = nil) {
        notificationsPresenter.showTestNotification()
    }

    private func setExcludedRoutes(_ excludedRoutes: [IPAddressRange], completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            self.excludedRoutes = excludedRoutes
            try? await updateTunnelConfiguration(selectedServer: selectedServerStore.selectedServer, reassert: false)
            completionHandler?(nil)
        }
    }

    private func setIncludedRoutes(_ includedRoutes: [IPAddressRange], completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            self.includedRoutes = includedRoutes
            try? await updateTunnelConfiguration(selectedServer: selectedServerStore.selectedServer, reassert: false)
            completionHandler?(nil)
        }
    }

    private func simulateTunnelFailure(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            os_log("Simulating tunnel failure", log: .networkProtection, type: .info)

            adapter.stop { error in
                if let error {
                    os_log("🔵 Failed to stop WireGuard adapter: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)
                }

                completionHandler?(error.map { ExtensionMessageString($0.localizedDescription).rawValue })
            }
        }
    }

    // MARK: - Adapter start completion handling

    /// Called when the adapter reports that the tunnel was successfully started.
    ///
    private func handleAdapterStarted(resumed: Bool = false) async {
        if !resumed {
            connectionStatus = .connected(connectedDate: Date())
        }

        guard !isKeyExpired else {
            await rekey()
            return
        }

        os_log("🔵 Tunnel interface is %{public}@", log: .networkProtection, type: .info, adapter.interfaceName ?? "unknown")

        if isConnectionTesterEnabled, let interfaceName = adapter.interfaceName {
            do {
                try await connectionTester.start(tunnelIfName: interfaceName)
            } catch {
                os_log("🔵 Error: the VPN connection tester could not be started: %{public}@",
                       log: .networkProtection,
                       type: .error,
                       error.localizedDescription)
            }
        } else if isConnectionTesterEnabled {
            os_log("🔵 Error: the VPN connection tester could not be started since we could not retrieve the tunnel interface name",
                   log: .networkProtection,
                   type: .error)
        } else {
            os_log("🔵 VPN connection tester disabled", log: .networkProtection, type: .error)
        }
    }

    public func handleAdapterStopped() async {
        connectionStatus = .disconnected
        await self.connectionTester.stop()
    }

    // MARK: - Computer sleeping

    public override func sleep() async {
        os_log("Sleep", log: .networkProtectionSleepLog, type: .info)

        await connectionTester.stop()
    }

    public override func wake() {
        os_log("Wake up", log: .networkProtectionSleepLog, type: .info)

        Task {
            await handleAdapterStarted(resumed: true)
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
