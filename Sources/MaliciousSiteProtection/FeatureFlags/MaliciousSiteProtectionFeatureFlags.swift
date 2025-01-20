//
//  MaliciousSiteProtectionFeatureFlags.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit

public protocol MaliciousSiteProtectionFeatureFlagger {
    /// A Boolean value indicating whether malicious site protection is enabled.
    /// - Returns: `true` if malicious site protection is enabled; otherwise, `false`.
    var isMaliciousSiteProtectionEnabled: Bool { get }

    /// Checks if should detect malicious threats for a specific domain.
    /// - Parameter domain: The domain to check for malicious threat.
    /// - Returns: `true` if should check for malicious threats for the specified domain; otherwise, `false`.
    func shouldDetectMaliciousThreat(forDomain domain: String?) -> Bool
}

public protocol MaliciousSiteProtectionFeatureFlagsSettingsProvider {
    /// The frequency, in minutes, at which the hash prefix should be updated.
    var hashPrefixUpdateFrequency: Int { get }
    /// The frequency, in minutes, at which the filter set should be updated.
    var filterSetUpdateFrequency: Int { get }
}

/// An enum representing the different settings for malicious site protection feature flags.
public enum MaliciousSiteProtectionFeatureSettings: String {
    /// The setting for hash prefix update frequency.
    case hashPrefixUpdateFrequency
    /// The setting for filter set update frequency.
    case filterSetUpdateFrequency

    public var defaultValue: Int {
        switch self {
        case .hashPrefixUpdateFrequency: return 20 // Default frequency for hash prefix updates is 20 minutes.
        case .filterSetUpdateFrequency: return 720 // Default frequency for filter set updates is 720 minutes (12 hours).
        }
    }
}

public struct MaliciousSiteProtectionFeatureFlags {
    private let featureFlagger: FeatureFlagger
    private let privacyConfigManager: PrivacyConfigurationManaging

    private var remoteSettings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        privacyConfigManager.privacyConfig.settings(for: .maliciousSiteProtection)
    }

    init(
        featureFlagger: FeatureFlagger,
        privacyConfigManager: PrivacyConfigurationManaging
    ) {
        self.featureFlagger = featureFlagger
        self.privacyConfigManager = privacyConfigManager
    }
}

// MARK: - MaliciousSiteProtectionFeatureFlagger

extension MaliciousSiteProtectionFeatureFlags: MaliciousSiteProtectionFeatureFlagger {

    public var isMaliciousSiteProtectionEnabled: Bool {
        privacyConfigManager.privacyConfig.isSubfeatureEnabled(MaliciousSiteProtectionSubfeature.onByDefault)
    }

    public func shouldDetectMaliciousThreat(forDomain domain: String?) -> Bool {
        isMaliciousSiteProtectionEnabled && privacyConfigManager.privacyConfig.isFeature(.maliciousSiteProtection, enabledForDomain: domain)
    }

}

// MARK: - MaliciousSiteProtectionFeatureFlagsSettingsProvider

extension MaliciousSiteProtectionFeatureFlags: MaliciousSiteProtectionFeatureFlagsSettingsProvider {

    public var hashPrefixUpdateFrequency: Int {
        getSettings(MaliciousSiteProtectionFeatureSettings.hashPrefixUpdateFrequency)
    }
    
    public var filterSetUpdateFrequency: Int {
        getSettings(MaliciousSiteProtectionFeatureSettings.filterSetUpdateFrequency)
    }

    private func getSettings(_ value: MaliciousSiteProtectionFeatureSettings) -> Int {
        remoteSettings[value.rawValue] as? Int ?? value.defaultValue
    }

}
