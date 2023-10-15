//
//  TunnelSettings.swift
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

import Combine
import Foundation

/// Persists tunnel settings.
///
/// It's strongly recommended to use shared `UserDefaults` to initialize this class, as `TunnelSettingsUpdater`
/// can then detect settings changes using KVO even if they're applied by a different process or even by the user through
/// the command line.
///
public final class TunnelSettings {

    public enum SelectedServer: Codable, Equatable {
        case automatic
        case endpoint(String)

        public var stringValue: String? {
            switch self {
            case .automatic: return nil
            case .endpoint(let endpoint): return endpoint
            }
        }
    }

    public enum Change: Codable {
        case setIncludeAllNetworks(_ includeAllNetworks: Bool)
        case setEnforceRoutes(_ enforceRoutes: Bool)
        case setSelectedServer(_ selectedServer: SelectedServer)
    }

    private let defaults: UserDefaults

    private(set) public lazy var changePublisher: AnyPublisher<Change, Never> = {

        let includeAllNetworksPublisher = includeAllNetworksPublisher.map { includeAllNetworks in
            Change.setIncludeAllNetworks(includeAllNetworks)
        }.eraseToAnyPublisher()

        let enforceRoutesPublisher = enforceRoutesPublisher.map { enforceRoutes in
            Change.setEnforceRoutes(enforceRoutes)
        }.eraseToAnyPublisher()

        let serverChangePublisher = selectedServerPublisher.map { server in
            Change.setSelectedServer(server)
        }.eraseToAnyPublisher()

        return Publishers.MergeMany(
            includeAllNetworksPublisher,
            enforceRoutesPublisher,
            serverChangePublisher).eraseToAnyPublisher()
    }()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK - Resetting to Defaults

    public func resetToDefaults() {
        defaults.resetNetworkProtectionSettingEnforceRoutes()
        defaults.resetNetworkProtectionSettingIncludeAllNetworks()
        defaults.resetNetworkProtectionSettingSelectedServer()
    }

    // MARK: - Registration Key Validity
/*
    @UserDefaultsWrapper(key: .networkProtectionRegistrationKeyValidity, defaultValue: nil)
    var registrationKeyValidity: TimeInterval? {
        didSet {
            Task {
                await sendRegistrationKeyValidityToProvider()
            }
        }
    }

    private let ipcClient: TunnelControllerIPCClient
    private let networkProtectionFeatureDisabler: NetworkProtectionFeatureDisabler

    // MARK: - Login Items Management

    private let loginItemsManager: LoginItemsManager

    // MARK: - Server Selection

    private let selectedServerStore = NetworkProtectionSelectedServerUserDefaultsStore()

    // MARK: - Initializers

    init(loginItemsManager: LoginItemsManager = .init()) {
        self.loginItemsManager = loginItemsManager

        let ipcClient = TunnelControllerIPCClient(machServiceName: Bundle.main.vpnMenuAgentBundleId)

        self.ipcClient = ipcClient
        self.networkProtectionFeatureDisabler = NetworkProtectionFeatureDisabler(ipcClient: ipcClient)
    }

    // MARK: - Debug commands for the extension

    func resetAllState(keepAuthToken: Bool) async throws {
        networkProtectionFeatureDisabler.disable(keepAuthToken: keepAuthToken, uninstallSystemExtension: true)

        NetworkProtectionWaitlist().waitlistStorage.deleteWaitlistState()
        DefaultWaitlistActivationDateStore().removeDates()
        DefaultNetworkProtectionRemoteMessagingStorage().removeStoredAndDismissedMessages()

        UserDefaults().removeObject(forKey: UserDefaultsWrapper<Bool>.Key.networkProtectionTermsAndConditionsAccepted.rawValue)
        NotificationCenter.default.post(name: .networkProtectionWaitlistAccessChanged, object: nil)
    }

    func removeSystemExtensionAndAgents() async throws {
        await networkProtectionFeatureDisabler.resetAllStateForVPNApp(uninstallSystemExtension: true)
        networkProtectionFeatureDisabler.disableLoginItems()
    }

    func sendTestNotificationRequest() async throws {
        guard let activeSession = try? await ConnectionSessionUtilities.activeSession() else {
            return
        }

        try? activeSession.sendProviderMessage(.triggerTestNotification)
    }

    // MARK: - Registation Key

    private func sendRegistrationKeyValidityToProvider() async {
        guard let activeSession = try? await ConnectionSessionUtilities.activeSession() else {
            return
        }

        try? activeSession.sendProviderMessage(.setKeyValidity(registrationKeyValidity))
    }

    func expireRegistrationKeyNow() async {
        guard let activeSession = try? await ConnectionSessionUtilities.activeSession() else {
            return
        }

        try? activeSession.sendProviderMessage(.expireRegistrationKey)
    }*/

    // MARK: - Enforce Routes

    public var includeAllNetworksPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingIncludeAllNetworksPublisher
    }

    public var includeAllNetworks: Bool {
        get {
            defaults.networkProtectionSettingIncludeAllNetworks
        }

        set {
            defaults.networkProtectionSettingIncludeAllNetworks = newValue
        }
    }

    // MARK: - Enforce Routes

    public var enforceRoutesPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingEnforceRoutesPublisher
    }

    public var enforceRoutes: Bool {
        get {
            defaults.networkProtectionSettingEnforceRoutes
        }

        set {
            defaults.networkProtectionSettingEnforceRoutes = newValue
        }
    }

    // MARK: - Server Selection

    public var selectedServerPublisher: AnyPublisher<SelectedServer, Never> {
        defaults.networkProtectionSettingSelectedServerPublisher
    }

    public var selectedServer: SelectedServer {
        get {
            defaults.networkProtectionSettingSelectedServer
        }

        set {
            defaults.networkProtectionSettingSelectedServer = newValue
        }
    }
}
