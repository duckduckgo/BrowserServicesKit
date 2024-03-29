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

// swiftlint:disable file_length

import Combine
import Common
import Foundation
import NetworkExtension
import UserNotifications

// swiftlint:disable:next type_body_length
open class PacketTunnelProvider: NEPacketTunnelProvider {

    public enum Event {
        case userBecameActive
        case reportConnectionAttempt(attempt: ConnectionAttempt)
        case tunnelStartAttempt(_ step: TunnelStartAttemptStep)
        case tunnelUpdateAttempt(_ step: TunnelUpdateAttemptStep)
        case reportTunnelFailure(result: NetworkProtectionTunnelFailureMonitor.Result)
        case reportLatency(result: NetworkProtectionLatencyMonitor.Result)
        case rekeyAttempt(_ step: RekeyAttemptStep)
    }

    public enum AttemptStep {
        case begin
        case success
        case failure(_ error: Error)
    }

    public typealias TunnelStartAttemptStep = AttemptStep
    public typealias TunnelUpdateAttemptStep = AttemptStep
    public typealias RekeyAttemptStep = AttemptStep

    public enum ConnectionAttempt {
        case connecting
        case success
        case failure
    }

    // MARK: - Error Handling

    enum TunnelError: LocalizedError, CustomNSError {
        // Tunnel Setup Errors - 0+
        case startingTunnelWithoutAuthToken
        case couldNotGenerateTunnelConfiguration(internalError: Error)
        case simulateTunnelFailureError

        // Subscription Errors - 100+
        case vpnAccessRevoked

        var errorDescription: String? {
            switch self {
            case .startingTunnelWithoutAuthToken:
                return "Missing auth token at startup"
            case .vpnAccessRevoked:
                return "VPN disconnected due to expired subscription"
            case .couldNotGenerateTunnelConfiguration(let internalError):
                return "Failed to generate a tunnel configuration: \(internalError.localizedDescription)"
            case .simulateTunnelFailureError:
                return "Simulated a tunnel error as requested"
            }
        }

        var errorCode: Int {
            switch self {
                // Tunnel Setup Errors - 0+
            case .startingTunnelWithoutAuthToken: return 0
            case .couldNotGenerateTunnelConfiguration: return 1
            case .simulateTunnelFailureError: return 2
                // Subscription Errors - 100+
            case .vpnAccessRevoked: return 100
            }
        }

        var errorUserInfo: [String: Any] {
            switch self {
            case .startingTunnelWithoutAuthToken,
                    .simulateTunnelFailureError,
                    .vpnAccessRevoked:
                return [:]
            case .couldNotGenerateTunnelConfiguration(let underlyingError):
                return [NSUnderlyingErrorKey: underlyingError]
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

    @MainActor
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

    @MainActor
    public var connectionStatus: ConnectionStatus = .default {
        didSet {
            guard connectionStatus != oldValue else {
                return
            }

            if case .connected = connectionStatus {
                self.notificationsPresenter.showConnectedNotification(serverLocation: lastSelectedServerInfo?.serverLocation)
            }

            handleConnectionStatusChange(old: oldValue, new: connectionStatus)
        }
    }

    public var isKillSwitchEnabled: Bool {
        guard #available(macOS 11.0, iOS 14.2, *) else { return false }
        return self.protocolConfiguration.enforceRoutes || self.protocolConfiguration.includeAllNetworks
    }

    // MARK: - Tunnel Settings

    private let settings: VPNSettings

    // MARK: - User Defaults

    private let defaults: UserDefaults

    // MARK: - Server Selection

    public var lastSelectedServerInfo: NetworkProtectionServerInfo? {
        didSet {
            lastSelectedServerInfoPublisher.send(lastSelectedServerInfo)
        }
    }

    public let lastSelectedServerInfoPublisher = CurrentValueSubject<NetworkProtectionServerInfo?, Never>(nil)

    private var includedRoutes: [IPAddressRange]?

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
        guard let currentExpirationDate = keyStore.currentExpirationDate else {
            return true
        }

        return currentExpirationDate <= Date()
    }

    private func rekeyIfExpired() async {
        os_log("Checking if rekey is necessary...", log: .networkProtectionKeyManagement)

        guard isKeyExpired else {
            os_log("The key is not expired", log: .networkProtectionKeyManagement)
            return
        }

        await rekey()
    }

    private func rekey() async {
        providerEvents.fire(.userBecameActive)

        // Experimental option to disable rekeying.
        guard !settings.disableRekeying else {
            os_log("Rekeying disabled", log: .networkProtectionKeyManagement)
            return
        }

        os_log("Rekeying...", log: .networkProtectionKeyManagement)
        providerEvents.fire(.rekeyAttempt(.begin))

        do {
            try await updateTunnelConfiguration(reassert: false, regenerateKey: true)
            providerEvents.fire(.rekeyAttempt(.success))
        } catch {
            os_log("Rekey attempt failed.  This is not an error if you're using debug Key Management options: %{public}@", log: .networkProtectionKeyManagement, type: .error, String(describing: error))
            providerEvents.fire(.rekeyAttempt(.failure(error)))
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

            // This provides a more frequent active user pixel check
            providerEvents.fire(.userBecameActive)

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

    // MARK: - Most recent handshake

    public func mostRecentHandshake() async -> TimeInterval? {
        try? await adapter.getMostRecentHandshake()
    }

    // MARK: - Connection tester

    private var isConnectionTesterEnabled: Bool = true

    @MainActor
    private lazy var connectionTester: NetworkProtectionConnectionTester = {
        NetworkProtectionConnectionTester(timerQueue: timerQueue, log: .networkProtectionConnectionTesterLog) { @MainActor [weak self] result in
            guard let self else { return }

            switch result {
            case .connected:
                self.tunnelHealth.isHavingConnectivityIssues = false
                self.updateBandwidthAnalyzerAndRekeyIfExpired()

            case .reconnected:
                self.tunnelHealth.isHavingConnectivityIssues = false
                self.updateBandwidthAnalyzerAndRekeyIfExpired()

            case .disconnected(let failureCount):
                self.tunnelHealth.isHavingConnectivityIssues = true
                self.bandwidthAnalyzer.reset()
            }
        }
    }()

    public lazy var tunnelFailureMonitor = NetworkProtectionTunnelFailureMonitor(tunnelProvider: self)
    public lazy var latencyMonitor = NetworkProtectionLatencyMonitor()
    public lazy var entitlementMonitor = NetworkProtectionEntitlementMonitor()

    private var lastTestFailed = false
    private let bandwidthAnalyzer = NetworkProtectionConnectionBandwidthAnalyzer()
    private let tunnelHealth: NetworkProtectionTunnelHealthStore
    private let controllerErrorStore: NetworkProtectionTunnelErrorStore

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializers

    private let keychainType: KeychainType
    private let debugEvents: EventMapping<NetworkProtectionError>?
    private let providerEvents: EventMapping<Event>

    public let isSubscriptionEnabled: Bool
    public let entitlementCheck: (() async -> Result<Bool, Error>)?

    public init(notificationsPresenter: NetworkProtectionNotificationsPresenter,
                tunnelHealthStore: NetworkProtectionTunnelHealthStore,
                controllerErrorStore: NetworkProtectionTunnelErrorStore,
                keychainType: KeychainType,
                tokenStore: NetworkProtectionTokenStore,
                debugEvents: EventMapping<NetworkProtectionError>?,
                providerEvents: EventMapping<Event>,
                settings: VPNSettings,
                defaults: UserDefaults,
                isSubscriptionEnabled: Bool,
                entitlementCheck: (() async -> Result<Bool, Error>)?) {
        os_log("[+] PacketTunnelProvider", log: .networkProtectionMemoryLog, type: .debug)

        self.notificationsPresenter = notificationsPresenter
        self.keychainType = keychainType
        self.tokenStore = tokenStore
        self.debugEvents = debugEvents
        self.providerEvents = providerEvents
        self.tunnelHealth = tunnelHealthStore
        self.controllerErrorStore = controllerErrorStore
        self.settings = settings
        self.defaults = defaults
        self.isSubscriptionEnabled = isSubscriptionEnabled
        self.entitlementCheck = isSubscriptionEnabled ? entitlementCheck : nil

        super.init()

        observeSettingChanges()
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
        loadSelectedEnvironment(from: options)
        loadSelectedServer(from: options)
        loadSelectedLocation(from: options)
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

    private func loadSelectedEnvironment(from options: StartupOptions) {
        switch options.selectedEnvironment {
        case .set(let selectedEnvironment):
            settings.selectedEnvironment = selectedEnvironment
        case .useExisting:
            break
        case .reset:
            settings.selectedEnvironment = .default
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

    private func loadSelectedLocation(from options: StartupOptions) {
        switch options.selectedLocation {
        case .set(let selectedServer):
            settings.selectedLocation = selectedServer
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
        case .set(let newAuthToken):
            if let currentAuthToken = try? tokenStore.fetchToken(), currentAuthToken == newAuthToken {
                return
            }

            try tokenStore.store(newAuthToken)
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
    }

    // MARK: - Observing Changes

    private func observeSettingChanges() {
        settings.changePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleSettingsChange(change)
            }.store(in: &cancellables)
    }

    @MainActor
    open func handleConnectionStatusChange(old: ConnectionStatus, new: ConnectionStatus) {
        os_log("⚫️ Connection Status Change: %{public}s -> %{public}s", log: .networkProtectionPixel, type: .debug, old.description, new.description)

        switch (old, new) {
        case (_, .connecting), (_, .reasserting):
            providerEvents.fire(.reportConnectionAttempt(attempt: .connecting))
        case (_, .connected):
            providerEvents.fire(.reportConnectionAttempt(attempt: .success))
        case (.connecting, _), (.reasserting, _):
            providerEvents.fire(.reportConnectionAttempt(attempt: .failure))
        default:
            break
        }
    }

    // MARK: - Overrideable Connection Events

    open func prepareToConnect(using provider: NETunnelProviderProtocol?) {
        // no-op: abstract method to be overridden in subclass
    }

    // MARK: - Tunnel Start

    open override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            providerEvents.fire(.tunnelStartAttempt(.begin))
            prepareToConnect(using: tunnelProviderProtocol)

            connectionStatus = .connecting

            let startupOptions = StartupOptions(options: options ?? [:])
            os_log("Starting tunnel with options: %{public}s", log: .networkProtection, startupOptions.description)

            resetIssueStateOnTunnelStart(startupOptions)

            let internalCompletionHandler = { [weak self, providerEvents] (error: Error?) in
                guard let error else {
                    completionHandler(nil)
                    providerEvents.fire(.tunnelStartAttempt(.success))
                    return
                }

                let handler = {
                    let errorDescription = (error as? LocalizedError)?.localizedDescription ?? String(describing: error)

                    os_log("Tunnel startup error: %{public}@", type: .error, errorDescription)
                    self?.controllerErrorStore.lastErrorMessage = errorDescription
                    self?.connectionStatus = .disconnected

                    providerEvents.fire(.tunnelStartAttempt(.failure(error)))
                    completionHandler(error)
                }

                if startupOptions.startupMethod == .automaticOnDemand {
                    Task {
                        // We add a 10 seconds delay when the VPN is started by
                        // on-demand and there's an error, to avoid frenetic ON/OFF
                        // cycling.
                        try? await Task.sleep(interval: .seconds(10))
                        handler()
                    }
                } else {
                    handler()
                }
            }

            startTunnel(options: startupOptions, completionHandler: internalCompletionHandler)
        }
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
        startTunnel(environment: settings.selectedEnvironment,
                    onDemand: onDemand,
                    completionHandler: completionHandler)
    }

    var currentServerSelectionMethod: NetworkProtectionServerSelectionMethod {
        var serverSelectionMethod: NetworkProtectionServerSelectionMethod

        switch settings.selectedLocation {
        case .nearest:
            serverSelectionMethod = .automatic
        case .location(let networkProtectionSelectedLocation):
            serverSelectionMethod = .preferredLocation(networkProtectionSelectedLocation)
        }

        switch settings.selectedServer {
        case .automatic:
            break
        case .endpoint(let string):
            // Selecting a specific server will override locations setting
            // Only available in debug
            serverSelectionMethod = .preferredServer(serverName: string)
        }

        return serverSelectionMethod
    }

    private func startTunnel(environment: VPNSettings.SelectedEnvironment, onDemand: Bool, completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                os_log("🔵 Generating tunnel config", log: .networkProtection, type: .info)
                os_log("🔵 Excluded ranges are: %{public}@", log: .networkProtection, type: .info, String(describing: settings.excludedRanges))
                os_log("🔵 Server selection method: %{public}@", log: .networkProtection, type: .info, currentServerSelectionMethod.debugDescription)
                let tunnelConfiguration = try await generateTunnelConfiguration(environment: environment,
                                                                                serverSelectionMethod: currentServerSelectionMethod,
                                                                                includedRoutes: includedRoutes ?? [],
                                                                                excludedRoutes: settings.excludedRanges,
                                                                                regenerateKey: true)
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

            Task { @MainActor [weak self] in
                // It's important to call this completion handler before running the tester
                // as if we don't, the tester will just fail.  It seems like the connection
                // won't fully work until the completion handler is called.
                completionHandler(nil)

                guard let self else { return }

                do {
                    let startReason: AdapterStartReason = onDemand ? .onDemand : .manual
                    try await self.handleAdapterStarted(startReason: startReason)
                } catch {
                    self.cancelTunnelWithError(error)
                    return
                }
            }
        }
    }

    // MARK: - Tunnel Stop

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {

        Task { @MainActor in
            await stopMonitors()

            connectionStatus = .disconnecting
            os_log("Stopping tunnel with reason %{public}@", log: .networkProtection, type: .info, String(describing: reason))

            adapter.stop { [weak self] error in
                if let error {
                    os_log("🔵 Failed to stop WireGuard adapter: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)
                    self?.debugEvents?.fire(error.networkProtectionError)
                }

                Task { [weak self] in
                    if let self {
                        self.handleAdapterStopped()

                        if case .superceded = reason {
                            self.notificationsPresenter.showSupersededNotification()
                        }
                    }

                    completionHandler()
                }
            }
        }
    }

    /// Do not cancel, directly... call this method so that the adapter and tester are stopped too.
    @MainActor
    private func cancelTunnel(with stopError: Error) async {
        await stopMonitors()

        connectionStatus = .disconnecting

        os_log("Stopping tunnel with error %{public}@", log: .networkProtection, type: .info, stopError.localizedDescription)

        self.adapter.stop { [weak self] error in
            guard let self else { return }

            if let error = error {
                os_log("Error while stopping adapter: %{public}@", log: .networkProtection, type: .info, error.localizedDescription)
                debugEvents?.fire(error.networkProtectionError)
            }

            cancelTunnelWithError(stopError)
            self.handleAdapterStopped()
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

    // MARK: - Tunnel Configuration

    @MainActor
    public func updateTunnelConfiguration(reassert: Bool, regenerateKey: Bool = false) async throws {
        try await updateTunnelConfiguration(
            environment: settings.selectedEnvironment,
            serverSelectionMethod: currentServerSelectionMethod,
            reassert: reassert,
            regenerateKey: regenerateKey
        )
    }

    @MainActor
    public func updateTunnelConfiguration(environment: VPNSettings.SelectedEnvironment = .default,
                                          serverSelectionMethod: NetworkProtectionServerSelectionMethod,
                                          reassert: Bool,
                                          regenerateKey: Bool = false) async throws {

        providerEvents.fire(.tunnelUpdateAttempt(.begin))

        if reassert {
            await stopMonitors()
        }

        do {
            let tunnelConfiguration = try await generateTunnelConfiguration(environment: environment,
                                                                            serverSelectionMethod: serverSelectionMethod,
                                                                            includedRoutes: includedRoutes ?? [],
                                                                            excludedRoutes: settings.excludedRanges,
                                                                            regenerateKey: regenerateKey)

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
                        if reassert {
                            do {
                                try await self?.handleAdapterStarted(startReason: .reconnected)
                            } catch {
                                continuation.resume(throwing: error)
                                return
                            }
                        }

                        continuation.resume()
                    }
                }
            }

            providerEvents.fire(.tunnelUpdateAttempt(.success))
        } catch {
            providerEvents.fire(.tunnelUpdateAttempt(.failure(error)))
        }
    }

    @MainActor
    private func generateTunnelConfiguration(environment: VPNSettings.SelectedEnvironment = .default,
                                             serverSelectionMethod: NetworkProtectionServerSelectionMethod,
                                             includedRoutes: [IPAddressRange],
                                             excludedRoutes: [IPAddressRange],
                                             regenerateKey: Bool) async throws -> TunnelConfiguration {

        let configurationResult: (TunnelConfiguration, NetworkProtectionServerInfo)

        do {
            let networkClient = NetworkProtectionBackendClient(environment: environment,
                                                               isSubscriptionEnabled: isSubscriptionEnabled)
            let deviceManager = NetworkProtectionDeviceManager(networkClient: networkClient,
                                                               tokenStore: tokenStore,
                                                               keyStore: keyStore,
                                                               errorEvents: debugEvents,
                                                               isSubscriptionEnabled: isSubscriptionEnabled)

            configurationResult = try await deviceManager.generateTunnelConfiguration(
                selectionMethod: serverSelectionMethod,
                includedRoutes: includedRoutes,
                excludedRoutes: excludedRoutes,
                isKillSwitchEnabled: isKillSwitchEnabled,
                regenerateKey: regenerateKey
            )
        } catch {
            if isSubscriptionEnabled, let error = error as? NetworkProtectionError, case .vpnAccessRevoked = error {
                await handleInvalidEntitlement(attemptsShutdown: true)
                throw TunnelError.vpnAccessRevoked
            }

            throw TunnelError.couldNotGenerateTunnelConfiguration(internalError: error)
        }

        let selectedServerInfo = configurationResult.1
        self.lastSelectedServerInfo = selectedServerInfo

        os_log("🔵 Generated tunnel configuration for server at location: %{public}s (preferred server is %{public}s)",
               log: .networkProtection,
               selectedServerInfo.serverLocation,
               selectedServerInfo.name)
        os_log("🔵 Excluded routes: %{public}@", log: .networkProtection, type: .info, String(describing: excludedRoutes))

        return configurationResult.0
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
            handleRequest(request, completionHandler: completionHandler)
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
        case .setExcludedRoutes:
            // No longer supported, will remove, but keeping the enum to prevent ABI issues
            completionHandler?(nil)
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
        case .getConnectionThroughput:
            getConnectionThroughput(completionHandler: completionHandler)
        }
    }

    // MARK: - App Requests: Handling

    private func handleRequest(_ request: ExtensionRequest, completionHandler: ((Data?) -> Void)? = nil) {
        switch request {
        case .changeTunnelSetting(let change):
            handleSettingChangeAppRequest(change, completionHandler: completionHandler)
            completionHandler?(nil)
        case .debugCommand(let command):
            handleDebugCommand(command, completionHandler: completionHandler)
        }
    }

    private func handleSettingChangeAppRequest(_ change: VPNSettings.Change, completionHandler: ((Data?) -> Void)? = nil) {
        settings.apply(change: change)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleSettingsChange(_ change: VPNSettings.Change, completionHandler: ((Data?) -> Void)? = nil) {
        switch change {
        case .setExcludeLocalNetworks:
            Task { @MainActor in
                if case .connected = connectionStatus {
                    try? await updateTunnelConfiguration(reassert: false)
                }
                completionHandler?(nil)
            }
        case .setSelectedServer(let selectedServer):
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            switch selectedServer {
            case .automatic:
                serverSelectionMethod = .automatic
            case .endpoint(let serverName):
                serverSelectionMethod = .preferredServer(serverName: serverName)
            }

            Task { @MainActor in
                if case .connected = connectionStatus {
                    try? await updateTunnelConfiguration(environment: settings.selectedEnvironment, serverSelectionMethod: serverSelectionMethod, reassert: true)
                }
                completionHandler?(nil)
            }
        case .setSelectedLocation(let selectedLocation):
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            switch selectedLocation {
            case .nearest:
                serverSelectionMethod = .automatic
            case .location(let location):
                serverSelectionMethod = .preferredLocation(location)
            }

            Task { @MainActor in
                if case .connected = connectionStatus {
                    try? await updateTunnelConfiguration(environment: settings.selectedEnvironment, serverSelectionMethod: serverSelectionMethod, reassert: true)
                }
                completionHandler?(nil)
            }
        case .setConnectOnLogin,
                .setIncludeAllNetworks,
                .setEnforceRoutes,
                .setNotifyStatusChanges,
                .setRegistrationKeyValidity,
                .setSelectedEnvironment,
                .setShowInMenuBar,
                .setDisableRekeying:
            // Intentional no-op, as some setting changes don't require any further operation
            completionHandler?(nil)
        }
    }

    private func handleDebugCommand(_ command: DebugCommand, completionHandler: ((Data?) -> Void)? = nil) {
        switch command {
        case .removeSystemExtension:
            // Since the system extension is being removed we may as well reset all state
            handleResetAllState(completionHandler: completionHandler)
        case .expireRegistrationKey:
            handleExpireRegistrationKey(completionHandler: completionHandler)
        case .sendTestNotification:
            handleSendTestNotification(completionHandler: completionHandler)
        case .disableConnectOnDemandAndShutDown:
            Task { [weak self] in
                await self?.attemptShutdown {
                    completionHandler?(nil)
                }
            }
        case .removeVPNConfiguration:
            // Since the VPN configuration is being removed we may as well reset all state
            handleResetAllState(completionHandler: completionHandler)
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
        Task { @MainActor in
            guard let serverName else {
                if case .endpoint = settings.selectedServer {
                    settings.selectedServer = .automatic

                    if case .connected = connectionStatus {
                        try? await updateTunnelConfiguration(reassert: true)
                    }
                }
                completionHandler?(nil)
                return
            }

            guard settings.selectedServer.stringValue != serverName else {
                completionHandler?(nil)
                return
            }

            settings.selectedServer = .endpoint(serverName)
            if case .connected = connectionStatus {
                try? await updateTunnelConfiguration(environment: settings.selectedEnvironment, serverSelectionMethod: .preferredServer(serverName: serverName), reassert: true)
            }
            completionHandler?(nil)
        }
    }

    private func handleGetServerLocation(completionHandler: ((Data?) -> Void)? = nil) {
        guard let attributes = lastSelectedServerInfo?.attributes else {
            completionHandler?(nil)
            return
        }

        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(attributes), let encodedJSONString = String(data: encoded, encoding: .utf8) else {
            assertionFailure("Failed to encode server attributes")
            completionHandler?(nil)
            return
        }

        completionHandler?(ExtensionMessageString(encodedJSONString).rawValue)
    }

    private func handleGetServerAddress(completionHandler: ((Data?) -> Void)? = nil) {
        let response = lastSelectedServerInfo?.endpoint.map { ExtensionMessageString($0.host.hostWithoutPort) }
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

    @available(iOS 17, *)
    public func handleShutDown(completionHandler: ((Data?) -> Void)? = nil) {
        Task { @MainActor in
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            guard let manager = managers.first else {
                completionHandler?(nil)
                return
            }

            os_log("🔵 Disabling Connect On Demand and shutting down the tunnel", log: .networkProtection, type: .info)

            manager.isOnDemandEnabled = false
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            let error = NSError(domain: "com.duckduckgo.vpn", code: 0)
            await cancelTunnel(with: error)

            completionHandler?(nil)
        }
    }

    private func setIncludedRoutes(_ includedRoutes: [IPAddressRange], completionHandler: ((Data?) -> Void)? = nil) {
        Task { @MainActor in
            self.includedRoutes = includedRoutes

            if case .connected = connectionStatus {
                try? await updateTunnelConfiguration(reassert: false)
            }
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
        Task { @MainActor in
            connectionTester.failNextTest()
            completionHandler?(nil)
        }
    }

    private func getConnectionThroughput(completionHandler: ((Data?) -> Void)? = nil) {
        Task { @MainActor in
            guard let (received, sent) = try? await adapter.getBytesTransmitted() else {
                completionHandler?(nil)
                return
            }

            let string = "\(received),\(sent)"
            completionHandler?(ExtensionMessageString(string).rawValue)
        }
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
    @MainActor
    private func handleAdapterStarted(startReason: AdapterStartReason) async throws {
        if startReason != .reconnected && startReason != .wake {
            connectionStatus = .connected(connectedDate: Date())
        }

        if !settings.disableRekeying {
            guard !isKeyExpired else {
                await rekey()
                return
            }
        }

        os_log("🔵 Tunnel interface is %{public}@", log: .networkProtection, type: .info, adapter.interfaceName ?? "unknown")

        // These cases only make sense in the context of a connection that had trouble
        // and is being fixed, so we want to test the connection immediately.
        let testImmediately = startReason == .reconnected || startReason == .onDemand
        try await startMonitors(testImmediately: testImmediately)
    }

    @MainActor
    public func handleAdapterStopped() {
        connectionStatus = .disconnected
    }

    // MARK: - Monitors

    private func startTunnelFailureMonitor() async {
        if await tunnelFailureMonitor.isStarted {
            await tunnelFailureMonitor.stop()
        }

        if isSubscriptionEnabled, await isEntitlementInvalid() {
            return
        }

        await tunnelFailureMonitor.start { [weak self] result in
            self?.providerEvents.fire(.reportTunnelFailure(result: result))
        }
    }

    private func startLatencyMonitor() async {
        guard let ip = lastSelectedServerInfo?.ipv4 else {
            await latencyMonitor.stop()
            return
        }
        if await latencyMonitor.isStarted {
            await latencyMonitor.stop()
        }

        if isSubscriptionEnabled, await isEntitlementInvalid() {
            return
        }

        await latencyMonitor.start(serverIP: ip) { [weak self] result in
            switch result {
            case .error:
                self?.providerEvents.fire(.reportLatency(result: .error))
            case .quality(let quality):
                self?.providerEvents.fire(.reportLatency(result: .quality(quality)))
            }
        }
    }

    private func startEntitlementMonitor() async {
        if await entitlementMonitor.isStarted {
            await entitlementMonitor.stop()
        }

        guard isSubscriptionEnabled, let entitlementCheck else { return }

        await entitlementMonitor.start(entitlementCheck: entitlementCheck) { [weak self] result in
            /// Attempt tunnel shutdown & show messaging iff the entitlement is verified to be invalid
            /// Ignore otherwise
            switch result {
            case .invalidEntitlement:
                Task { [weak self] in
                    await self?.handleInvalidEntitlement(attemptsShutdown: true)
                }
            case .validEntitlement, .error:
                break
            }
        }
    }

    @MainActor
    private func handleInvalidEntitlement(attemptsShutdown: Bool) async {
        defaults.enableEntitlementMessaging()
        notificationsPresenter.showEntitlementNotification()

        await stopMonitors()

        // We add a delay here so the notification has a chance to show up
        try? await Task.sleep(interval: .seconds(5))

        if attemptsShutdown {
            await attemptShutdown()
        }
    }

    // Attempt to shut down the tunnel
    // On iOS 16 and below, as a workaround, we rekey to force a 403 error so that the tunnel fails to restart
    @MainActor
    private func attemptShutdown(completion: (() -> Void)? = nil) async {
        if #available(iOS 17, *) {
            handleShutDown()
        } else {
            await rekey()
        }
        completion?()
    }

    @MainActor
    public func startMonitors(testImmediately: Bool) async throws {
        await startTunnelFailureMonitor()
        await startLatencyMonitor()
        await startEntitlementMonitor()

        do {
            try await startConnectionTester(testImmediately: testImmediately)
        } catch {
            os_log("🔵 Connection Tester error: %{public}@", log: .networkProtectionConnectionTesterLog, type: .error, String(reflecting: error))
            throw error
        }
    }

    @MainActor
    public func stopMonitors() async {
        await self.connectionTester.stop()
        await self.tunnelFailureMonitor.stop()
        await self.latencyMonitor.stop()
        await self.entitlementMonitor.stop()
    }

    // MARK: - Entitlement handling

    private func isEntitlementInvalid() async -> Bool {
        guard let entitlementCheck, case .success(false) = await entitlementCheck() else { return false }
        return true
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
        await tunnelFailureMonitor.stop()
        await latencyMonitor.stop()
        await entitlementMonitor.stop()
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

// swiftlint:enable file_length
