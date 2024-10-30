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
import os.log

open class PacketTunnelProvider: NEPacketTunnelProvider {

    public enum Event {
        case userBecameActive
        case connectionTesterStatusChange(_ status: ConnectionTesterStatus, server: String)
        case reportConnectionAttempt(attempt: ConnectionAttempt)
        case tunnelStartAttempt(_ step: TunnelStartAttemptStep)
        case tunnelStopAttempt(_ step: TunnelStopAttemptStep)
        case tunnelUpdateAttempt(_ step: TunnelUpdateAttemptStep)
        case tunnelWakeAttempt(_ step: TunnelWakeAttemptStep)
        case tunnelStartOnDemandWithoutAccessToken
        case reportTunnelFailure(result: NetworkProtectionTunnelFailureMonitor.Result)
        case reportLatency(result: NetworkProtectionLatencyMonitor.Result)
        case rekeyAttempt(_ step: RekeyAttemptStep)
        case failureRecoveryAttempt(_ step: FailureRecoveryStep)
        case serverMigrationAttempt(_ step: ServerMigrationAttemptStep)
    }

    public enum AttemptStep: CustomDebugStringConvertible {
        case begin
        case success
        case failure(_ error: Error)

        public var debugDescription: String {
            switch self {
            case .begin:
                "Begin"
            case .success:
                "Success"
            case .failure(let error):
                "Failure \(error.localizedDescription)"
            }
        }
    }

    public typealias TunnelStartAttemptStep = AttemptStep
    public typealias TunnelStopAttemptStep = AttemptStep
    public typealias TunnelUpdateAttemptStep = AttemptStep
    public typealias TunnelWakeAttemptStep = AttemptStep
    public typealias RekeyAttemptStep = AttemptStep
    public typealias ServerMigrationAttemptStep = AttemptStep

    public enum ConnectionAttempt: CustomDebugStringConvertible {
        case connecting
        case success
        case failure

        public var debugDescription: String {
            switch self {
            case .connecting:
                "Connecting"
            case .success:
                "Success"
            case .failure:
                "Failure"
            }
        }
    }

    public enum ConnectionTesterStatus {
        case failed(duration: Duration)
        case recovered(duration: Duration, failureCount: Int)

        public enum Duration: String {
            case immediate
            case extended
        }
    }

    // MARK: - Error Handling

    public enum TunnelError: LocalizedError, CustomNSError, SilentErrorConvertible {
        // Tunnel Setup Errors - 0+
        case startingTunnelWithoutAuthToken
        case couldNotGenerateTunnelConfiguration(internalError: Error)
        case simulateTunnelFailureError

        // Subscription Errors - 100+
        case vpnAccessRevoked

        // State Reset - 200+
        case appRequestedCancellation

        public var errorDescription: String? {
            switch self {
            case .startingTunnelWithoutAuthToken:
                return "Missing auth token at startup"
            case .vpnAccessRevoked:
                return "VPN disconnected due to expired subscription"
            case .couldNotGenerateTunnelConfiguration(let internalError):
                return "Failed to generate a tunnel configuration: \(internalError.localizedDescription)"
            case .simulateTunnelFailureError:
                return "Simulated a tunnel error as requested"
            case .appRequestedCancellation:
                return nil
            }
        }

        public var errorCode: Int {
            switch self {
                // Tunnel Setup Errors - 0+
            case .startingTunnelWithoutAuthToken: return 0
            case .couldNotGenerateTunnelConfiguration: return 1
            case .simulateTunnelFailureError: return 2
                // Subscription Errors - 100+
            case .vpnAccessRevoked: return 100
                // State Reset - 200+
            case .appRequestedCancellation: return 200
            }
        }

        public var errorUserInfo: [String: Any] {
            switch self {
            case .startingTunnelWithoutAuthToken,
                    .simulateTunnelFailureError,
                    .vpnAccessRevoked,
                    .appRequestedCancellation:
                return [:]
            case .couldNotGenerateTunnelConfiguration(let underlyingError):
                return [NSUnderlyingErrorKey: underlyingError]
            }
        }

        public var asSilentError: KnownFailure.SilentError? {
            guard case .couldNotGenerateTunnelConfiguration(let internalError) = self,
                  let clientError = internalError as? NetworkProtectionClientError,
                  case .failedToFetchRegisteredServers = clientError else {
                return nil
            }

            return .registeredServerFetchingFailed
        }
    }

    // MARK: - WireGuard

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self, wireGuardInterface: self.wireGuardInterface) { logLevel, message in
            if logLevel == .error {
                Logger.networkProtection.error("🔴 Received error from adapter: \(message, privacy: .public)")
            } else {
                Logger.networkProtection.log("Received message from adapter: \(message, privacy: .public)")
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
                self.notificationsPresenter.showConnectedNotification(
                    serverLocation: lastSelectedServerInfo?.serverLocation,
                    snoozeEnded: snoozeJustEnded
                )

                snoozeJustEnded = false
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

    private lazy var serverSelectionResolver: VPNServerSelectionResolving = {
        let locationRepository = NetworkProtectionLocationListCompositeRepository(
            environment: settings.selectedEnvironment,
            tokenStore: tokenStore,
            errorEvents: debugEvents
        )
        return VPNServerSelectionResolver(locationListRepository: locationRepository, vpnSettings: settings)
    }()

    @MainActor
    private var lastSelectedServer: NetworkProtectionServer? {
        didSet {
            lastSelectedServerInfoPublisher.send(lastSelectedServer?.serverInfo)
        }
    }

    @MainActor
    public var lastSelectedServerInfo: NetworkProtectionServerInfo? {
        lastSelectedServer?.serverInfo
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
        Logger.networkProtectionKeyManagement.log("Resetting the current registration key")
        keyStore.resetCurrentKeyPair()
    }

    private var isKeyExpired: Bool {
        guard let currentExpirationDate = keyStore.currentExpirationDate else {
            return true
        }

        return currentExpirationDate <= Date()
    }

    private func rekeyIfExpired() async {
        Logger.networkProtectionKeyManagement.log("Checking if rekey is necessary...")

        guard isKeyExpired else {
            Logger.networkProtectionKeyManagement.log("The key is not expired")
            return
        }

        try? await rekey()
    }

    private func rekey() async throws {
        providerEvents.fire(.userBecameActive)

        // Experimental option to disable rekeying.
        guard !settings.disableRekeying else {
            Logger.networkProtectionKeyManagement.log("Rekeying disabled")
            return
        }

        providerEvents.fire(.rekeyAttempt(.begin))

        do {
            try await updateTunnelConfiguration(
                updateMethod: .selectServer(currentServerSelectionMethod),
                reassert: false,
                regenerateKey: true)
            providerEvents.fire(.rekeyAttempt(.success))
        } catch {
            providerEvents.fire(.rekeyAttempt(.failure(error)))
            await subscriptionAccessErrorHandler(error)
            throw error
        }
    }

    private func subscriptionAccessErrorHandler(_ error: Error) async {
        switch error {
        case TunnelError.vpnAccessRevoked:
            await handleAccessRevoked(attemptsShutdown: true)
        default:
            break
        }
    }

    private func setKeyValidity(_ interval: TimeInterval?) {
        if let interval {
            let firstExpirationDate = Date().addingTimeInterval(interval)
            Logger.networkProtectionKeyManagement.log("Setting key validity interval to \(String(describing: interval), privacy: .public) seconds (next expiration date \(String(describing: firstExpirationDate), privacy: .public))")
            settings.registrationKeyValidity = .custom(interval)
        } else {
            Logger.networkProtectionKeyManagement.log("Resetting key validity interval")
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

    // MARK: - Connection tester

    private static let connectionTesterExtendedFailuresCount = 8
    private var isConnectionTesterEnabled: Bool = true

    @MainActor
    private lazy var connectionTester: NetworkProtectionConnectionTester = {
        NetworkProtectionConnectionTester(timerQueue: timerQueue) { @MainActor [weak self] result in
            guard let self else { return }

            let serverName = lastSelectedServerInfo?.name ?? "Unknown"

            switch result {
            case .connected:
                self.tunnelHealth.isHavingConnectivityIssues = false
                self.updateBandwidthAnalyzerAndRekeyIfExpired()

            case .reconnected(let failureCount):
                providerEvents.fire(
                    .connectionTesterStatusChange(
                        .recovered(duration: .immediate, failureCount: failureCount),
                        server: serverName))

                if failureCount >= Self.connectionTesterExtendedFailuresCount {
                    providerEvents.fire(
                        .connectionTesterStatusChange(
                            .recovered(duration: .extended, failureCount: failureCount),
                            server: serverName))
                }

                self.tunnelHealth.isHavingConnectivityIssues = false
                self.updateBandwidthAnalyzerAndRekeyIfExpired()

            case .disconnected(let failureCount):
                if failureCount == 1 {
                    providerEvents.fire(
                        .connectionTesterStatusChange(
                            .failed(duration: .immediate),
                            server: serverName))
                } else if failureCount == 8 {
                    providerEvents.fire(
                        .connectionTesterStatusChange(
                            .failed(duration: .extended),
                            server: serverName))
                }

                self.tunnelHealth.isHavingConnectivityIssues = true
                self.bandwidthAnalyzer.reset()
            }
        }
    }()

    private lazy var deviceManager: NetworkProtectionDeviceManagement = NetworkProtectionDeviceManager(
        environment: self.settings.selectedEnvironment,
        tokenStore: self.tokenStore,
        keyStore: self.keyStore,
        errorEvents: self.debugEvents
    )

    private lazy var tunnelFailureMonitor = NetworkProtectionTunnelFailureMonitor(handshakeReporter: adapter)

    public lazy var latencyMonitor = NetworkProtectionLatencyMonitor()
    public lazy var entitlementMonitor = NetworkProtectionEntitlementMonitor()
    public lazy var serverStatusMonitor = NetworkProtectionServerStatusMonitor(
        networkClient: NetworkProtectionBackendClient(environment: self.settings.selectedEnvironment),
        tokenStore: self.tokenStore
    )

    private var lastTestFailed = false
    private let bandwidthAnalyzer = NetworkProtectionConnectionBandwidthAnalyzer()
    private let tunnelHealth: NetworkProtectionTunnelHealthStore
    private let controllerErrorStore: NetworkProtectionTunnelErrorStore
    private let knownFailureStore: NetworkProtectionKnownFailureStore
    private let snoozeTimingStore: NetworkProtectionSnoozeTimingStore
    private let wireGuardInterface: WireGuardInterface

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializers

    private let keychainType: KeychainType
    private let debugEvents: EventMapping<NetworkProtectionError>
    private let providerEvents: EventMapping<Event>
    public let entitlementCheck: (() async -> Result<Bool, Error>)?

    public init(notificationsPresenter: NetworkProtectionNotificationsPresenter,
                tunnelHealthStore: NetworkProtectionTunnelHealthStore,
                controllerErrorStore: NetworkProtectionTunnelErrorStore,
                knownFailureStore: NetworkProtectionKnownFailureStore = NetworkProtectionKnownFailureStore(),
                snoozeTimingStore: NetworkProtectionSnoozeTimingStore,
                wireGuardInterface: WireGuardInterface,
                keychainType: KeychainType,
                tokenStore: NetworkProtectionTokenStore,
                debugEvents: EventMapping<NetworkProtectionError>,
                providerEvents: EventMapping<Event>,
                settings: VPNSettings,
                defaults: UserDefaults,
                entitlementCheck: (() async -> Result<Bool, Error>)?) {
        Logger.networkProtectionMemory.debug("[+] PacketTunnelProvider")

        self.notificationsPresenter = notificationsPresenter
        self.keychainType = keychainType
        self.tokenStore = tokenStore
        self.debugEvents = debugEvents
        self.providerEvents = providerEvents
        self.tunnelHealth = tunnelHealthStore
        self.controllerErrorStore = controllerErrorStore
        self.knownFailureStore = knownFailureStore
        self.snoozeTimingStore = snoozeTimingStore
        self.wireGuardInterface = wireGuardInterface
        self.settings = settings
        self.defaults = defaults
        self.entitlementCheck = entitlementCheck

        super.init()

        observeSettingChanges()
    }

    deinit {
        Logger.networkProtectionMemory.debug("[-] PacketTunnelProvider")
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
        loadDNSSettings(from: options)
        loadTesterEnabled(from: options)
#if os(macOS)
        try loadAuthToken(from: options)
#endif
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
        case .set(let selectedLocation):
            settings.selectedLocation = selectedLocation
        case .useExisting:
            break
        case .reset:
            settings.selectedServer = .automatic
        }
    }

    private func loadDNSSettings(from options: StartupOptions) {
        switch options.dnsSettings {
        case .set(let dnsSettings):
            settings.dnsSettings = dnsSettings
        case .useExisting:
            break
        case .reset:
            settings.dnsSettings = .default
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

#if os(macOS)
    private func loadAuthToken(from options: StartupOptions) throws {
        switch options.authToken {
        case .set(let newAuthToken):
            if let currentAuthToken = try? tokenStore.fetchToken(), currentAuthToken == newAuthToken {
                return
            }

            try tokenStore.store(newAuthToken)
        case .useExisting:
            guard try tokenStore.fetchToken() != nil else {
                throw TunnelError.startingTunnelWithoutAuthToken
            }
        case .reset:
            // This case should in theory not be possible, but it's ideal to have this in place
            // in case an error in the controller on the client side allows it.
            try tokenStore.deleteToken()
            throw TunnelError.startingTunnelWithoutAuthToken
        }
    }
#endif

    private func loadRoutes(from options: [String: Any]?) {
        self.includedRoutes = (options?[NetworkProtectionOptionKey.includedRoutes] as? [String])?.compactMap(IPAddressRange.init(from:)) ?? []
    }

    // MARK: - Observing Changes

    private func observeSettingChanges() {
        settings.changePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                let handleSettingsChange = handleSettingsChange
                let subscriptionAccessErrorHandler = subscriptionAccessErrorHandler

                Task { @MainActor in
                    do {
                        try await handleSettingsChange(change)
                    } catch {
                        await subscriptionAccessErrorHandler(error)
                        throw error
                    }
                }
            }.store(in: &cancellables)
    }

    @MainActor
    open func handleConnectionStatusChange(old: ConnectionStatus, new: ConnectionStatus) {
        Logger.networkProtectionPixel.debug("⚫️ Connection Status Change: \(old.description, privacy: .public) -> \(new.description, privacy: .public)")

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

    @MainActor
    open override func startTunnel(options: [String: NSObject]? = nil) async throws {

        // It's important to have this as soon as possible since it helps setup PixelKit
        prepareToConnect(using: tunnelProviderProtocol)

        let startupOptions = StartupOptions(options: options ?? [:])
        Logger.networkProtection.log("Starting tunnel with options: \(startupOptions.description, privacy: .public)")

        // Reset snooze if the VPN is restarting.
        self.snoozeTimingStore.reset()

        do {
            try load(options: startupOptions)
            try loadVendorOptions(from: tunnelProviderProtocol)

            if (try? tokenStore.fetchToken()) == nil {
                throw TunnelError.startingTunnelWithoutAuthToken
            }
        } catch {
            if startupOptions.startupMethod == .automaticOnDemand {
                // If the VPN was started by on-demand without the basic prerequisites for
                // it to work we skip firing pixels.  This should only be possible if the
                // manual start attempt that preceded failed, or if the subscription has
                // expired.  In either case it should be enough to record the manual failures
                // for these prerequisited to avoid flooding our metrics.
                providerEvents.fire(.tunnelStartOnDemandWithoutAccessToken)
                try await Task.sleep(interval: .seconds(15))
            } else {
                // If the VPN was started manually without the basic prerequisites we always
                // want to know as this should not be possible.
                providerEvents.fire(.tunnelStartAttempt(.begin))
                providerEvents.fire(.tunnelStartAttempt(.failure(error)))
            }

            Logger.networkProtection.log("🔴 Stopping VPN due to no auth token")
            await attemptShutdownDueToRevokedAccess()

            throw error
        }

        do {
            providerEvents.fire(.tunnelStartAttempt(.begin))
            connectionStatus = .connecting
            resetIssueStateOnTunnelStart(startupOptions)

            try runDebugSimulations(options: startupOptions)
            try await startTunnel(onDemand: startupOptions.startupMethod == .automaticOnDemand)

            providerEvents.fire(.tunnelStartAttempt(.success))
        } catch {
            if startupOptions.startupMethod == .automaticOnDemand {
                // We add a delay when the VPN is started by
                // on-demand and there's an error, to avoid frenetic ON/OFF
                // cycling.
                try await Task.sleep(interval: .seconds(15))
            }

            let errorDescription = (error as? LocalizedError)?.localizedDescription ?? String(describing: error)

            self.controllerErrorStore.lastErrorMessage = errorDescription
            self.connectionStatus = .disconnected
            self.knownFailureStore.lastKnownFailure = KnownFailure(error)

            providerEvents.fire(.tunnelStartAttempt(.failure(error)))
            throw error
        }
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

    private func startTunnel(onDemand: Bool) async throws {
        do {
            Logger.networkProtection.log("Generating tunnel config")
            Logger.networkProtection.log("Excluded ranges are: \(String(describing: self.settings.excludedRanges), privacy: .public)")
            Logger.networkProtection.log("Server selection method: \(self.currentServerSelectionMethod.debugDescription, privacy: .public)")
            Logger.networkProtection.log("DNS server: \(String(describing: self.settings.dnsSettings), privacy: .public)")
            let tunnelConfiguration = try await generateTunnelConfiguration(serverSelectionMethod: currentServerSelectionMethod,
                                                                            includedRoutes: includedRoutes ?? [],
                                                                            excludedRoutes: settings.excludedRanges,
                                                                            dnsSettings: settings.dnsSettings,
                                                                            regenerateKey: true)
            try await startTunnel(with: tunnelConfiguration, onDemand: onDemand)
            Logger.networkProtection.log("Done generating tunnel config")
        } catch {
            controllerErrorStore.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func startTunnel(with tunnelConfiguration: TunnelConfiguration, onDemand: Bool) async throws {

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            adapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] error in
                if let error {
                    self?.debugEvents.fire(error.networkProtectionError)
                    continuation.resume(throwing: error)
                    return
                }

                Task { @MainActor [weak self] in
                    // It's important to call this completion handler before running the tester
                    // as if we don't, the tester will just fail.  It seems like the connection
                    // won't fully work until the completion handler is called.
                    continuation.resume()

                    guard let self else { return }

                    do {
                        let startReason: AdapterStartReason = onDemand ? .onDemand : .manual
                        try await self.handleAdapterStarted(startReason: startReason)

                        // Enable Connect on Demand when manually enabling the tunnel on iOS 17.0+.
#if os(iOS)
                        if #available(iOS 17.0, *), startReason == .manual {
                            try? await updateConnectOnDemand(enabled: true)
                            Logger.networkProtection.log("Enabled Connect on Demand due to user-initiated startup")
                        }
#endif
                    } catch {
                        self.cancelTunnelWithError(error)
                        return
                    }
                }
            }
        }
    }

    // MARK: - Tunnel Stop

    @MainActor
    open override func stopTunnel(with reason: NEProviderStopReason) async {
        providerEvents.fire(.tunnelStopAttempt(.begin))

        Logger.networkProtection.log("Stopping tunnel with reason \(String(describing: reason), privacy: .public)")

        do {
            try await stopTunnel()
            providerEvents.fire(.tunnelStopAttempt(.success))

            // Disable Connect on Demand when disabling the tunnel from iOS settings on iOS 17.0+.
            if #available(iOS 17.0, *), case .userInitiated = reason {
                try? await updateConnectOnDemand(enabled: false)
                Logger.networkProtection.log("Disabled Connect on Demand due to user-initiated shutdown")
            }
        } catch {
            providerEvents.fire(.tunnelStopAttempt(.failure(error)))
        }

        if case .userInitiated = reason {
            // If the user shut down the VPN deliberately, end snooze mode early.
            self.snoozeTimingStore.reset()
        }

        if case .superceded = reason {
            self.notificationsPresenter.showSupersededNotification()
        }
    }

    /// Do not cancel, directly... call this method so that the adapter and tester are stopped too.
    @MainActor
    private func cancelTunnel(with stopError: Error) async {
        providerEvents.fire(.tunnelStopAttempt(.begin))

        Logger.networkProtection.error("Stopping tunnel with error \(stopError.localizedDescription, privacy: .public)")

        do {
            try await stopTunnel()
            providerEvents.fire(.tunnelStopAttempt(.success))
        } catch {
            providerEvents.fire(.tunnelStopAttempt(.failure(error)))
        }

        cancelTunnelWithError(stopError)
    }

    // MARK: - Tunnel Stop: Support Methods

    /// Do not call this directly.  Call `stopTunnel(with:)` or `cancelTunnel(with:)` instead.
    ///
    @MainActor
    private func stopTunnel() async throws {
        connectionStatus = .disconnecting
        await stopMonitors()
        try await stopAdapter()
    }

    @MainActor
    private func stopAdapter() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            adapter.stop { [weak self] error in
                if let self {
                    self.handleAdapterStopped()
                }

                if let error {
                    self?.debugEvents.fire(error.networkProtectionError)

                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume()
            }
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

    enum TunnelUpdateMethod {
        case selectServer(_ method: NetworkProtectionServerSelectionMethod)
        case useConfiguration(_ configuration: TunnelConfiguration)
    }

    @MainActor
    func updateTunnelConfiguration(updateMethod: TunnelUpdateMethod,
                                   reassert: Bool,
                                   regenerateKey: Bool = false) async throws {

        providerEvents.fire(.tunnelUpdateAttempt(.begin))

        if reassert {
            await stopMonitors()
        }

        do {
            let tunnelConfiguration: TunnelConfiguration

            switch updateMethod {
            case .selectServer(let serverSelectionMethod):
                tunnelConfiguration = try await generateTunnelConfiguration(serverSelectionMethod: serverSelectionMethod,
                                                                            includedRoutes: includedRoutes ?? [],
                                                                            excludedRoutes: settings.excludedRanges,
                                                                            dnsSettings: settings.dnsSettings,
                                                                            regenerateKey: regenerateKey)

            case .useConfiguration(let newTunnelConfiguration):
                tunnelConfiguration = newTunnelConfiguration
            }

            try await updateAdapterConfiguration(tunnelConfiguration: tunnelConfiguration, reassert: reassert)

            if reassert {
                try await handleAdapterStarted(startReason: .reconnected)
            }

            providerEvents.fire(.tunnelUpdateAttempt(.success))
        } catch {
            providerEvents.fire(.tunnelUpdateAttempt(.failure(error)))

            switch error {
            case WireGuardAdapterError.setWireguardConfig:
                await cancelTunnel(with: error)
            default:
                break
            }

            throw error
        }
    }

    @MainActor
    private func updateAdapterConfiguration(tunnelConfiguration: TunnelConfiguration, reassert: Bool) async throws {

        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self = self else {
                continuation.resume()
                return
            }

            self.adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: reassert) { [weak self] error in

                if let error = error {
                    self?.debugEvents.fire(error.networkProtectionError)

                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume()
            }
        }
    }

    @MainActor
    private func generateTunnelConfiguration(serverSelectionMethod: NetworkProtectionServerSelectionMethod,
                                             includedRoutes: [IPAddressRange],
                                             excludedRoutes: [IPAddressRange],
                                             dnsSettings: NetworkProtectionDNSSettings,
                                             regenerateKey: Bool) async throws -> TunnelConfiguration {

        let configurationResult: NetworkProtectionDeviceManager.GenerateTunnelConfigurationResult
        let resolvedServerSelectionMethod = await serverSelectionResolver.resolvedServerSelectionMethod()

        do {
            configurationResult = try await deviceManager.generateTunnelConfiguration(
                resolvedSelectionMethod: resolvedServerSelectionMethod,
                includedRoutes: includedRoutes,
                excludedRoutes: excludedRoutes,
                dnsSettings: dnsSettings,
                isKillSwitchEnabled: isKillSwitchEnabled,
                regenerateKey: regenerateKey
            )
        } catch {
            if let error = error as? NetworkProtectionError, case .vpnAccessRevoked = error {
                throw TunnelError.vpnAccessRevoked
            }

            throw TunnelError.couldNotGenerateTunnelConfiguration(internalError: error)
        }

        let newSelectedServer = configurationResult.server
        self.lastSelectedServer = newSelectedServer

        Logger.networkProtection.log("⚪️ Generated tunnel configuration for server at location: \(newSelectedServer.serverInfo.serverLocation, privacy: .public) (preferred server is \(newSelectedServer.serverInfo.name, privacy: .public))")
        Logger.networkProtection.log("Excluded routes: \(String(describing: excludedRoutes), privacy: .public)")

        return configurationResult.tunnelConfiguration
    }

    @available(iOS 17.0, *)
    private func updateConnectOnDemand(enabled: Bool) async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let manager = managers.first {
            manager.isOnDemandEnabled = enabled
            try await manager.saveToPreferences()
        }
    }

    // MARK: - App Messages

    @MainActor public override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {

        guard let message = ExtensionMessage(rawValue: messageData) else {
            Logger.networkProtectionIPC.error("🔴 Received unknown app message")
            completionHandler?(nil)
            return
        }

        /// We're skipping messages that are very frequent and not likely to affect anything in terms of functionality.
        /// We can opt to aggregate them somehow if we ever need them - for now I'm disabling.
        if message != .getDataVolume {
            Logger.networkProtectionIPC.log("⚪️ Received app message: \(String(describing: message), privacy: .public)")
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
        case .getDataVolume:
            getDataVolume(completionHandler: completionHandler)
        case .startSnooze(let duration):
            startSnooze(duration, completionHandler: completionHandler)
        case .cancelSnooze:
            cancelSnooze(completionHandler: completionHandler)
        }
    }

    // MARK: - App Requests: Handling

    private func handleRequest(_ request: ExtensionRequest, completionHandler: ((Data?) -> Void)? = nil) {
        switch request {
        case .changeTunnelSetting(let change):
            handleSettingChangeAppRequest(change, completionHandler: completionHandler)
            completionHandler?(nil)
        case .command(let command):
            handle(command, completionHandler: completionHandler)
        }
    }

    private func handleSettingChangeAppRequest(_ change: VPNSettings.Change, completionHandler: ((Data?) -> Void)? = nil) {
        settings.apply(change: change)
    }

    @MainActor
    private func handleSettingsChange(_ change: VPNSettings.Change) async throws {
        switch change {
        case .setExcludeLocalNetworks:
            if case .connected = connectionStatus {
                try await updateTunnelConfiguration(
                    updateMethod: .selectServer(currentServerSelectionMethod),
                    reassert: false)
            }
        case .setSelectedServer(let selectedServer):
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            switch selectedServer {
            case .automatic:
                serverSelectionMethod = .automatic
            case .endpoint(let serverName):
                serverSelectionMethod = .preferredServer(serverName: serverName)
            }

            if case .connected = connectionStatus {
                try? await updateTunnelConfiguration(
                    updateMethod: .selectServer(serverSelectionMethod),
                    reassert: true)
            }
        case .setSelectedLocation(let selectedLocation):
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            switch selectedLocation {
            case .nearest:
                serverSelectionMethod = .automatic
            case .location(let location):
                serverSelectionMethod = .preferredLocation(location)
            }

            if case .connected = connectionStatus {
                try? await updateTunnelConfiguration(
                    updateMethod: .selectServer(serverSelectionMethod),
                    reassert: true)
            }
        case .setDNSSettings:
            if case .connected = connectionStatus {
                try? await updateTunnelConfiguration(
                    updateMethod: .selectServer(currentServerSelectionMethod),
                    reassert: true)
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
            break
        }
    }

    private func handle(_ command: VPNCommand, completionHandler: ((Data?) -> Void)? = nil) {
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
                await self?.attemptShutdownDueToRevokedAccess()
                completionHandler?(nil)
            }
        case .removeVPNConfiguration:
            // Since the VPN configuration is being removed we may as well reset all state
            handleResetAllState(completionHandler: completionHandler)
        case .restartAdapter:
            handleRestartAdapter(completionHandler: completionHandler)
        case .uninstallVPN:
            // Since the VPN configuration is being removed we may as well reset all state
            handleResetAllState(completionHandler: completionHandler)
        case .quitAgent:
            // No-op since this is intended for the agent app
            break
        }
    }

    // MARK: - App Messages: Handling

    private func handleExpireRegistrationKey(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            try? await rekey()
            completionHandler?(nil)
        }
    }

    private func handleResetAllState(completionHandler: ((Data?) -> Void)? = nil) {
        resetRegistrationKey()

#if os(macOS)
        try? tokenStore.deleteToken()
#endif

        Task {
            completionHandler?(nil)
            await cancelTunnel(with: TunnelError.appRequestedCancellation)
        }
    }

    private func handleRestartAdapter(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            do {
                let tunnelConfiguration = try await generateTunnelConfiguration(serverSelectionMethod: currentServerSelectionMethod,
                                                                                includedRoutes: includedRoutes ?? [],
                                                                                excludedRoutes: settings.excludedRanges,
                                                                                dnsSettings: settings.dnsSettings,
                                                                                regenerateKey: false)

                try await updateTunnelConfiguration(updateMethod: .useConfiguration(tunnelConfiguration),
                                                    reassert: false,
                                                    regenerateKey: false)

                completionHandler?(nil)
            } catch {
                completionHandler?(nil)
            }
        }
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
                        try? await updateTunnelConfiguration(
                            updateMethod: .selectServer(currentServerSelectionMethod),
                            reassert: true)
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
                try? await updateTunnelConfiguration(
                    updateMethod: .selectServer(.preferredServer(serverName: serverName)),
                    reassert: true)
            }
            completionHandler?(nil)
        }
    }

    @MainActor
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

    @MainActor
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
    @MainActor
    public func handleShutDown() async throws {
        Logger.networkProtection.log("🔴 Disabling Connect On Demand and shutting down the tunnel")
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()

        guard let manager = managers.first else {
            Logger.networkProtection.log("Could not find a viable manager, bailing out of shutdown")
            // Doesn't matter a lot what error we throw here, since we'll try cancelling the
            // tunnel.
            throw TunnelError.vpnAccessRevoked
        }

        manager.isOnDemandEnabled = false
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        await cancelTunnel(with: TunnelError.vpnAccessRevoked)
    }

    private func setIncludedRoutes(_ includedRoutes: [IPAddressRange], completionHandler: ((Data?) -> Void)? = nil) {
        Task { @MainActor in
            self.includedRoutes = includedRoutes

            if case .connected = connectionStatus {
                try? await updateTunnelConfiguration(
                    updateMethod: .selectServer(currentServerSelectionMethod),
                    reassert: false)
            }
            completionHandler?(nil)
        }
    }

    private func simulateTunnelFailure(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            Logger.networkProtection.log("Simulating tunnel failure")

            adapter.stop { [weak self] error in
                if let error {
                    self?.debugEvents.fire(error.networkProtectionError)
                    Logger.networkProtection.error("🔴 Failed to stop WireGuard adapter: \(error.localizedDescription, privacy: .public)")
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

    private func getDataVolume(completionHandler: ((Data?) -> Void)? = nil) {
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
        case snoozeEnded
    }

    /// Called when the adapter reports that the tunnel was successfully started.
    ///
    @MainActor
    private func handleAdapterStarted(startReason: AdapterStartReason) async throws {
        if startReason != .reconnected && startReason != .wake {
            connectionStatus = .connected(connectedDate: Date())
        }

        Logger.networkProtection.log("⚪️ Tunnel interface is \(self.adapter.interfaceName ?? "unknown", privacy: .public)")

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

        await tunnelFailureMonitor.start { [weak self] result in
            guard let self else {
                return
            }

            providerEvents.fire(.reportTunnelFailure(result: result))

            switch result {
            case .failureDetected:
                startServerFailureRecovery()
            case .failureRecovered:
                Task {
                    await self.failureRecoveryHandler.stop()
                }
            case .networkPathChanged: break
            }
        }
    }

    private lazy var failureRecoveryHandler: FailureRecoveryHandling = FailureRecoveryHandler(
        deviceManager: deviceManager,
        reassertingControl: self,
        eventHandler: { [weak self] step in
            self?.providerEvents.fire(.failureRecoveryAttempt(step))
        }
    )

    private func startServerFailureRecovery() {
        Task {
            guard let server = await self.lastSelectedServer else {
                return
            }
            await self.failureRecoveryHandler.attemptRecovery(
                to: server,
                includedRoutes: self.includedRoutes ?? [],
                excludedRoutes: self.settings.excludedRanges,
                dnsSettings: self.settings.dnsSettings,
                isKillSwitchEnabled: self.isKillSwitchEnabled
            ) { [weak self] generateConfigResult in
                try await self?.handleFailureRecoveryConfigUpdate(result: generateConfigResult)
                self?.providerEvents.fire(.failureRecoveryAttempt(.completed(.unhealthy)))
            }
        }
    }

    @MainActor
    private func handleFailureRecoveryConfigUpdate(result: NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult) async throws {
        self.lastSelectedServer = result.server
        try await updateTunnelConfiguration(updateMethod: .useConfiguration(result.tunnelConfiguration), reassert: true)
    }

    @MainActor
    private func startLatencyMonitor() async {
        guard let ip = lastSelectedServerInfo?.ipv4 else {
            await latencyMonitor.stop()
            return
        }
        if await latencyMonitor.isStarted {
            await latencyMonitor.stop()
        }

        if await isEntitlementInvalid() {
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

        guard let entitlementCheck else {
            assertionFailure("Expected entitlement check but didn't find one")
            return
        }

        await entitlementMonitor.start(entitlementCheck: entitlementCheck) { [weak self] result in
            /// Attempt tunnel shutdown & show messaging iff the entitlement is verified to be invalid
            /// Ignore otherwise
            switch result {
            case .invalidEntitlement:
                await self?.handleAccessRevoked(attemptsShutdown: true)
            case .validEntitlement, .error:
                break
            }
        }
    }

    private func startServerStatusMonitor() async {
        guard let serverName = await lastSelectedServerInfo?.name else {
            await serverStatusMonitor.stop()
            return
        }

        if await serverStatusMonitor.isStarted {
            await serverStatusMonitor.stop()
        }

        await serverStatusMonitor.start(serverName: serverName) { status in
            if status.shouldMigrate {
                Task { [ weak self] in
                    guard let self else { return }

                    providerEvents.fire(.serverMigrationAttempt(.begin))

                    do {
                        try await self.updateTunnelConfiguration(
                            updateMethod: .selectServer(currentServerSelectionMethod),
                            reassert: true,
                            regenerateKey: true)
                        providerEvents.fire(.serverMigrationAttempt(.success))
                    } catch {
                        providerEvents.fire(.serverMigrationAttempt(.failure(error)))
                    }
                }
            }
        }
    }

    @MainActor
    private func handleAccessRevoked(attemptsShutdown: Bool) async {
        defaults.enableEntitlementMessaging()
        notificationsPresenter.showEntitlementNotification()

        await stopMonitors()

        // We add a delay here so the notification has a chance to show up
        try? await Task.sleep(interval: .seconds(5))

        if attemptsShutdown {
            await attemptShutdownDueToRevokedAccess()
        }
    }

    /// Tries to shut down the tunnel after access has been revoked.
    ///
    /// iOS 17+ supports disabling on-demand, but macOS does not... so we resort to removing the subscription token
    /// which should prevent the VPN from even trying to start.
    ///
    @MainActor
    private func attemptShutdownDueToRevokedAccess() async {
        let cancelTunnel = {
#if os(macOS)
            try? self.tokenStore.deleteToken()
#endif
            self.cancelTunnelWithError(TunnelError.vpnAccessRevoked)
        }

        if #available(iOS 17, *) {
            do {
                try await handleShutDown()
            } catch {
                cancelTunnel()
            }
        } else {
            cancelTunnel()
        }
    }

    @MainActor
    public func startMonitors(testImmediately: Bool) async throws {
        await startTunnelFailureMonitor()
        await startLatencyMonitor()
        await startEntitlementMonitor()
        await startServerStatusMonitor()

        do {
            try await startConnectionTester(testImmediately: testImmediately)
        } catch {
            Logger.networkProtection.error("🔴 Connection Tester error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @MainActor
    public func stopMonitors() async {
        self.connectionTester.stop()
        await self.tunnelFailureMonitor.stop()
        await self.latencyMonitor.stop()
        await self.entitlementMonitor.stop()
        await self.serverStatusMonitor.stop()
    }

    // MARK: - Entitlement handling

    private func isEntitlementInvalid() async -> Bool {
        guard let entitlementCheck, case .success(false) = await entitlementCheck() else { return false }
        return true
    }

    // MARK: - Connection Tester

    private enum ConnectionTesterError: CustomNSError {
        case couldNotRetrieveInterfaceNameFromAdapter
        case testerFailedToStart(internalError: Error)

        var errorCode: Int {
            switch self {
            case .couldNotRetrieveInterfaceNameFromAdapter: return 0
            case .testerFailedToStart: return 1
            }
        }

        var errorUserInfo: [String: Any] {
            switch self {
            case .couldNotRetrieveInterfaceNameFromAdapter:
                return [:]
            case .testerFailedToStart(let internalError):
                return [NSUnderlyingErrorKey: internalError as NSError]
            }
        }
    }

    private func startConnectionTester(testImmediately: Bool) async throws {
        guard isConnectionTesterEnabled else {
            Logger.networkProtectionConnectionTester.log("The connection tester is disabled")
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
                Logger.networkProtectionConnectionTester.log("Printing current proposed utun: \(String(reflecting: self.adapter.interfaceName), privacy: .public)")
            default:
                break
            }

            throw ConnectionTesterError.testerFailedToStart(internalError: error)
        }
    }

    // MARK: - Computer sleeping

    @MainActor
    public override func sleep() async {
        Logger.networkProtectionSleep.log("Sleep")
        await stopMonitors()
    }

    @MainActor
    public override func wake() {
        Logger.networkProtectionSleep.log("Wake up")

        // macOS can launch the extension due to calls to `sendProviderMessage`, so there's
        // a chance this is being called when the VPN isn't really meant to be connected or
        // running.  We want to avoid firing pixels or handling adapter changes when this is
        // the case.
        guard connectionStatus != .disconnected else {
            return
        }

        Task {
            providerEvents.fire(.tunnelWakeAttempt(.begin))

            do {
                try await handleAdapterStarted(startReason: .wake)
                Logger.networkProtectionConnectionTester.log("🟢 Wake success")
                providerEvents.fire(.tunnelWakeAttempt(.success))
            } catch {
                Logger.networkProtection.error("🔴 Wake error: \(error.localizedDescription, privacy: .public)")
                providerEvents.fire(.tunnelWakeAttempt(.failure(error)))
            }
        }
    }

    // MARK: - Snooze

    private func startSnooze(_ duration: TimeInterval, completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            await startSnooze(duration: duration)
            completionHandler?(nil)
        }
    }

    private func cancelSnooze(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            await cancelSnooze()
            completionHandler?(nil)
        }
    }

    private var snoozeTimerTask: Task<Never, Error>? {
        willSet {
            snoozeTimerTask?.cancel()
        }
    }

    private var snoozeRequestProcessing: Bool = false
    private var snoozeJustEnded: Bool = false

    @MainActor
    private func startSnooze(duration: TimeInterval) async {
        if snoozeRequestProcessing {
            Logger.networkProtection.log("Rejecting start snooze request due to existing request processing")
            return
        }

        snoozeRequestProcessing = true
        Logger.networkProtection.log("Starting snooze mode with duration: \(duration, privacy: .public)")

        await stopMonitors()

        self.adapter.snooze { [weak self] error in
            guard let self else {
                assertionFailure("Failed to get strong self")
                return
            }

            if error == nil {
                self.connectionStatus = .snoozing
                self.snoozeTimingStore.activeTiming = .init(startDate: Date(), duration: duration)
                self.notificationsPresenter.showSnoozingNotification(duration: duration)

                snoozeTimerTask = Task.periodic(interval: .seconds(1)) { [weak self] in
                    guard let self else { return }

                    if self.snoozeTimingStore.hasExpired {
                        Task.detached {
                            Logger.networkProtection.log("Snooze mode timer expired, canceling snooze now...")
                            await self.cancelSnooze()
                        }
                    }
                }
            } else {
                self.snoozeTimingStore.reset()
            }

            self.snoozeRequestProcessing = false
        }
    }

    private func cancelSnooze() async {
        if snoozeRequestProcessing {
            Logger.networkProtection.log("Rejecting cancel snooze request due to existing request processing")
            return
        }

        snoozeRequestProcessing = true
        defer {
            snoozeRequestProcessing = false
        }

        snoozeTimerTask?.cancel()
        snoozeTimerTask = nil

        guard await connectionStatus == .snoozing, snoozeTimingStore.activeTiming != nil else {
            Logger.networkProtection.error("Failed to cancel snooze mode as it was not active")
            return
        }

        Logger.networkProtection.log("Canceling snooze mode")

        snoozeJustEnded = true
        try? await startTunnel(onDemand: false)
        snoozeTimingStore.reset()
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

        case .setWireguardConfig(let errorCode):
            return "Update tunnel failed with wgSetConfig returning: \(errorCode)"

        case .invalidState:
            return "Starting tunnel failed with invalid error"
        }
    }

    public var debugDescription: String {
        errorDescription!
    }
}
