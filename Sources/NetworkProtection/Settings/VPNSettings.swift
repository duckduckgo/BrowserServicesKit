//
//  VPNSettings.swift
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
import os.log

// swiftlint:disable type_body_length

/// Persists and publishes changes to tunnel settings.
///
/// It's strongly recommended to use shared `UserDefaults` to initialize this class, as `VPNSettings`
/// can then detect settings changes using KVO even if they're applied by a different process or even by the user through
/// the command line.
///
public final class VPNSettings {

    public enum Change: Codable {
        case setConnectOnLogin(_ connectOnLogin: Bool)
        case setIncludeAllNetworks(_ includeAllNetworks: Bool)
        case setEnforceRoutes(_ enforceRoutes: Bool)
        case setExcludeLocalNetworks(_ excludeLocalNetworks: Bool)
        case setNotifyStatusChanges(_ notifyStatusChanges: Bool)
        case setRegistrationKeyValidity(_ validity: RegistrationKeyValidity)
        case setSelectedServer(_ selectedServer: SelectedServer)
        case setSelectedLocation(_ selectedLocation: SelectedLocation)
        case setSelectedEnvironment(_ selectedEnvironment: SelectedEnvironment)
        case setShowInMenuBar(_ showInMenuBar: Bool)
    }

    public enum RegistrationKeyValidity: Codable, Equatable {
        case automatic
        case custom(_ timeInterval: TimeInterval)
    }

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

    public enum SelectedLocation: Codable, Equatable {
        case nearest
        case location(NetworkProtectionSelectedLocation)

        public var location: NetworkProtectionSelectedLocation? {
            switch self {
            case .nearest: return nil
            case .location(let location): return location
            }
        }
    }

    public enum SelectedEnvironment: String, Codable {
        case production
        case staging

        public static var `default`: SelectedEnvironment = .production

        public var endpointURL: URL {
            switch self {
            case .production:
                return URL(string: "https://controller.netp.duckduckgo.com")!
            case .staging:
                return URL(string: "https://staging1.netp.duckduckgo.com")!
            }
        }
    }

    private let defaults: UserDefaults
    private let log: OSLog

    public init(defaults: UserDefaults, log: OSLog = .disabled) {
        self.defaults = defaults
        self.log = log
    }

    // MARK: - Change Management

    private(set) public lazy var changePublisher: AnyPublisher<Change, Never> = {

        let logChange = { [weak self] (change: Change) in
            guard let self else { return }

            os_log("VPNSettings(%{public}@): publishing change %{public}@",
                   log: self.log,
                   type: .info,
                   String(describing: Bundle.main.bundleIdentifier!),
                   String(describing: change))
        }

        let connectOnLoginPublisher = connectOnLoginPublisher.map { connectOnLogin in
            Change.setConnectOnLogin(connectOnLogin)
        }.eraseToAnyPublisher()

        let includeAllNetworksPublisher = includeAllNetworksPublisher.map { includeAllNetworks in
            Change.setIncludeAllNetworks(includeAllNetworks)
        }.eraseToAnyPublisher()

        let enforceRoutesPublisher = enforceRoutesPublisher.map { enforceRoutes in
            Change.setEnforceRoutes(enforceRoutes)
        }.eraseToAnyPublisher()

        let excludeLocalNetworksPublisher = excludeLocalNetworksPublisher.map { excludeLocalNetworks in
            Change.setExcludeLocalNetworks(excludeLocalNetworks)
        }.eraseToAnyPublisher()

        let notifyStatusChangesPublisher = notifyStatusChangesPublisher.map { notifyStatusChanges in
            Change.setNotifyStatusChanges(notifyStatusChanges)
        }.eraseToAnyPublisher()

        let registrationKeyValidityPublisher = registrationKeyValidityPublisher.map { validity in
            Change.setRegistrationKeyValidity(validity)
        }.eraseToAnyPublisher()

        let serverChangePublisher = selectedServerPublisher.map { server in
            Change.setSelectedServer(server)
        }.eraseToAnyPublisher()

        let locationChangePublisher = selectedLocationPublisher.map { location in
            Change.setSelectedLocation(location)
        }.eraseToAnyPublisher()

        let environmentChangePublisher = selectedEnvironmentPublisher.map { environment in
            Change.setSelectedEnvironment(environment)
        }.eraseToAnyPublisher()

        let showInMenuBarPublisher = showInMenuBarPublisher.map { showInMenuBar in
            Change.setShowInMenuBar(showInMenuBar)
        }.eraseToAnyPublisher()

        return Publishers.MergeMany(
            connectOnLoginPublisher,
            includeAllNetworksPublisher,
            enforceRoutesPublisher,
            excludeLocalNetworksPublisher,
            notifyStatusChangesPublisher,
            serverChangePublisher,
            locationChangePublisher,
            environmentChangePublisher,
            showInMenuBarPublisher)
        .handleEvents(receiveOutput: { change in
            logChange(change)
        }).eraseToAnyPublisher()
    }()

    // MARK: - Resetting to Defaults

    public func resetToDefaults() {
        os_log("VPNSettings(%{public}@): resetting to defaults",
               log: log,
               type: .info,
               String(describing: Bundle.main.bundleIdentifier!))

        defaults.resetNetworkProtectionSettingConnectOnLogin()
        defaults.resetNetworkProtectionSettingEnforceRoutes()
        defaults.resetNetworkProtectionSettingExcludeLocalNetworks()
        defaults.resetNetworkProtectionSettingIncludeAllNetworks()
        defaults.resetNetworkProtectionSettingNotifyStatusChanges()
        defaults.resetNetworkProtectionSettingRegistrationKeyValidity()
        defaults.resetNetworkProtectionSettingSelectedServer()
        defaults.resetNetworkProtectionSettingSelectedEnvironment()
        defaults.resetNetworkProtectionSettingShowInMenuBar()
    }

    // MARK: - Applying Changes

    /// - Returns: true if the setting was truly changed.
    ///
    public func apply(change: Change) -> Bool {
        os_log("VPNSettings(%{public}@): applying change %{public}@",
               log: log,
               type: .info,
               String(describing: Bundle.main.bundleIdentifier!),
               String(describing: change))

        switch change {
        case .setConnectOnLogin(let connectOnLogin):
            guard self.connectOnLogin != connectOnLogin else {
                return false
            }
            self.connectOnLogin = connectOnLogin
        case .setEnforceRoutes(let enforceRoutes):
            guard self.enforceRoutes != enforceRoutes else {
                return false
            }
            self.enforceRoutes = enforceRoutes
        case .setExcludeLocalNetworks(let excludeLocalNetworks):
            guard self.excludeLocalNetworks != excludeLocalNetworks else {
                return false
            }
            self.excludeLocalNetworks = excludeLocalNetworks
        case .setIncludeAllNetworks(let includeAllNetworks):
            guard self.includeAllNetworks != includeAllNetworks else {
                return false
            }
            self.includeAllNetworks = includeAllNetworks
        case .setNotifyStatusChanges(let notifyStatusChanges):
            guard self.notifyStatusChanges != notifyStatusChanges else {
                return false
            }
            self.notifyStatusChanges = notifyStatusChanges
        case .setRegistrationKeyValidity(let registrationKeyValidity):
            guard self.registrationKeyValidity != registrationKeyValidity else {
                return false
            }
            self.registrationKeyValidity = registrationKeyValidity
        case .setSelectedServer(let selectedServer):
            guard self.selectedServer != selectedServer else {
                return false
            }
            self.selectedServer = selectedServer
        case .setSelectedLocation(let selectedLocation):
            guard self.selectedLocation != selectedLocation else {
                return false
            }
            self.selectedLocation = selectedLocation
        case .setSelectedEnvironment(let selectedEnvironment):
            guard self.selectedEnvironment != selectedEnvironment else {
                return false
            }
            self.selectedEnvironment = selectedEnvironment
        case .setShowInMenuBar(let showInMenuBar):
            guard self.showInMenuBar != showInMenuBar else {
                return false
            }
            self.showInMenuBar = showInMenuBar
        }

        return true
    }

    // MARK: - Connect on Login

    public var connectOnLoginPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingConnectOnLoginPublisher
    }

    public var connectOnLogin: Bool {
        get {
            defaults.networkProtectionSettingConnectOnLogin
        }

        set {
            defaults.networkProtectionSettingConnectOnLogin = newValue
        }
    }

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

    // MARK: - Exclude Local Routes

    public var excludeLocalNetworksPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingExcludeLocalNetworksPublisher
    }

    public var excludeLocalNetworks: Bool {
        get {
            defaults.networkProtectionSettingExcludeLocalNetworks
        }

        set {
            defaults.networkProtectionSettingExcludeLocalNetworks = newValue
        }
    }

    // MARK: - Registration Key Validity

    public var registrationKeyValidityPublisher: AnyPublisher<RegistrationKeyValidity, Never> {
        defaults.networkProtectionSettingRegistrationKeyValidityPublisher
    }

    public var registrationKeyValidity: RegistrationKeyValidity {
        get {
            defaults.networkProtectionSettingRegistrationKeyValidity
        }

        set {
            defaults.networkProtectionSettingRegistrationKeyValidity = newValue
        }
    }

    private var networkProtectionSettingRegistrationKeyValidityDefault: TimeInterval {
        .days(2)
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

    // MARK: - Location Selection

    public var selectedLocationPublisher: AnyPublisher<SelectedLocation, Never> {
        defaults.networkProtectionSettingSelectedLocationPublisher
    }

    public var selectedLocation: SelectedLocation {
        get {
            defaults.networkProtectionSettingSelectedLocation
        }

        set {
            defaults.networkProtectionSettingSelectedLocation = newValue
        }
    }

    // MARK: - Environment

    public var selectedEnvironmentPublisher: AnyPublisher<SelectedEnvironment, Never> {
        defaults.networkProtectionSettingSelectedEnvironmentPublisher
    }

    public var selectedEnvironment: SelectedEnvironment {
        get {
            defaults.networkProtectionSettingSelectedEnvironment
        }

        set {
            defaults.networkProtectionSettingSelectedEnvironment = newValue
        }
    }

    // MARK: - Show in Menu Bar

    public var showInMenuBarPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingShowInMenuBarPublisher
    }

    public var showInMenuBar: Bool {
        get {
            defaults.networkProtectionSettingShowInMenuBar
        }

        set {
            defaults.networkProtectionSettingShowInMenuBar = newValue
        }
    }

    // MARK: - Notify Status Changes

    public var notifyStatusChangesPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionNotifyStatusChangesPublisher
    }

    public var notifyStatusChanges: Bool {
        get {
            defaults.networkProtectionNotifyStatusChanges
        }

        set {
            defaults.networkProtectionNotifyStatusChanges = newValue
        }
    }

    // MARK: - Routes

    public var excludedRoutes: [RoutingRange] {
        var ipv4Ranges = RoutingRange.alwaysExcludedIPv4Ranges

        if excludeLocalNetworks {
            ipv4Ranges += RoutingRange.localNetworkRanges
        }

        return ipv4Ranges + RoutingRange.alwaysExcludedIPv6Ranges
    }

    public var excludedRanges: [IPAddressRange] {
        excludedRoutes.compactMap { entry in
            switch entry {
            case .section:
                // Nothing to map
                return nil
            case .range(let range, _):
                return range
            }
        }
    }
}

// swiftlint:enable type_body_length
