//
//  FeatureFlagger.swift
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

/// This protocol defines a common interface for feature flags managed by FeatureFlagger.
///
/// It should be implemented by the feature flag type in client apps.
///
public protocol FeatureFlagProtocol: CaseIterable {

    /// Returns a string representation of the flag, suitable for persisting the flag state to disk.
    var rawValue: String { get }

    /// Return `true` here if a flag can be locally overridden.
    ///
    /// Local overriding mechanism requires passing `FeatureFlagOverriding` instance to
    /// the `FeatureFlagger`. Then it will handle all feature flags that return `true` for
    /// this property.
    ///
    /// > Note: Local feature flag overriding is gated by the internal user flag and has no effect
    ///   as long as internal user flag is off.
    var supportsLocalOverriding: Bool { get }

    /// Defines the source of the feature flag, which corresponds to
    /// where the final flag value should come from.
    ///
    /// Example client implementation:
    ///
    /// ```
    /// public enum FeatureFlag: FeatureFlagProtocol {
    ///    case sync
    ///    case autofill
    ///    case cookieConsent
    ///    case duckPlayer
    ///
    ///    var source: FeatureFlagSource {
    ///        case .sync:
    ///            return .disabled
    ///        case .cookieConsent:
    ///            return .internalOnly
    ///        case .credentialsAutofill:
    ///            return .remoteDevelopment(.subfeature(AutofillSubfeature.credentialsAutofill))
    ///        case .duckPlayer:
    ///            return .remoteReleasable(.feature(.duckPlayer))
    ///    }
    /// }
    /// ```
    var source: FeatureFlagSource { get }
}

public enum FeatureFlagSource {
    /// Completely disabled in all configurations
    case disabled

    /// Enabled for internal users only. Cannot be toggled remotely
    case internalOnly

    /// Toggled remotely using PrivacyConfiguration but only for internal users. Otherwise, disabled.
    case remoteDevelopment(PrivacyConfigFeatureLevel)

    /// Toggled remotely using PrivacyConfiguration for all users
    case remoteReleasable(PrivacyConfigFeatureLevel)
}

public enum PrivacyConfigFeatureLevel {
    /// Corresponds to a given top-level privacy config feature
    case feature(PrivacyFeature)

    /// Corresponds to a given subfeature of a privacy config feature
    case subfeature(any PrivacySubfeature)
}

public protocol FeatureFlagger: AnyObject {
    var internalUserDecider: InternalUserDecider { get }

    /// Local feature flag overriding mechanism.
    ///
    /// This property is optional and if kept as `nil`, local overrides
    /// are not in use. Local overrides are only ever considered if a user
    /// is internal user.
    var localOverrides: FeatureFlagOverriding? { get }

    /// Called from app features to determine whether a given feature is enabled.
    ///
    /// Feature Flag's `source` is checked to determine if the flag should be toggled.
    /// If feature flagger provides overrides mechanism (`localOverrides` is not `nil`)
    /// and the user is internal, local overrides is checked first and if present,
    /// returned as flag value.
    ///
    func isFeatureOn<Flag: FeatureFlagProtocol>(for featureFlag: Flag, allowOverride: Bool) -> Bool
}

public class DefaultFeatureFlagger: FeatureFlagger {

    public let internalUserDecider: InternalUserDecider
    public let privacyConfigManager: PrivacyConfigurationManaging
    public let localOverrides: FeatureFlagOverriding?

    public init(
        internalUserDecider: InternalUserDecider,
        privacyConfigManager: PrivacyConfigurationManaging
    ) {
        self.internalUserDecider = internalUserDecider
        self.privacyConfigManager = privacyConfigManager
        self.localOverrides = nil
    }

    public init<Flag: FeatureFlagProtocol>(
        internalUserDecider: InternalUserDecider,
        privacyConfigManager: PrivacyConfigurationManaging,
        localOverrides: FeatureFlagOverriding,
        for: Flag.Type
    ) {
        self.internalUserDecider = internalUserDecider
        self.privacyConfigManager = privacyConfigManager
        self.localOverrides = localOverrides
        localOverrides.featureFlagger = self

        // Clear all overrides if not an internal user
        if !internalUserDecider.isInternalUser {
            localOverrides.clearAllOverrides(for: Flag.self)
        }
    }

    public func isFeatureOn<Flag: FeatureFlagProtocol>(for featureFlag: Flag, allowOverride: Bool = true) -> Bool {
        if allowOverride, internalUserDecider.isInternalUser, let localOverride = localOverrides?.override(for: featureFlag) {
            return localOverride
        }
        switch featureFlag.source {
        case .disabled:
            return false
        case .internalOnly:
            return internalUserDecider.isInternalUser
        case .remoteDevelopment(let featureType):
            guard internalUserDecider.isInternalUser else {
                return false
            }
            return isEnabled(featureType)
        case .remoteReleasable(let featureType):
            return isEnabled(featureType)
        }
    }

    private func isEnabled(_ featureType: PrivacyConfigFeatureLevel) -> Bool {
        switch featureType {
        case .feature(let feature):
            return privacyConfigManager.privacyConfig.isEnabled(featureKey: feature)
        case .subfeature(let subfeature):
            return privacyConfigManager.privacyConfig.isSubfeatureEnabled(subfeature)
        }
    }
}
