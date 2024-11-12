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

public protocol FeatureFlagger {

/// Called from app features to determine whether a given feature is enabled.
///
/// `forProvider: F` takes a FeatureFlag type defined by the respective app which defines from what source it should be toggled
/// see `FeatureFlagSourceProviding` comments below for more details
    func isFeatureOn<F: FeatureFlagSourceProviding>(forProvider: F) -> Bool
}

public class DefaultFeatureFlagger: FeatureFlagger {
    public let internalUserDecider: InternalUserDecider
    public let privacyConfigManager: PrivacyConfigurationManaging

    public init(internalUserDecider: InternalUserDecider, privacyConfigManager: PrivacyConfigurationManaging) {
        self.internalUserDecider = internalUserDecider
        self.privacyConfigManager = privacyConfigManager
    }

    public func isFeatureOn<F: FeatureFlagSourceProviding>(forProvider provider: F) -> Bool {
        switch provider.source {
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

/// To be implemented by the FeatureFlag enum type in the respective app. The source corresponds to
/// where the final value should come from.
///
/// Example:
///
/// ```
/// public enum FeatureFlag: FeatureFlagSourceProviding {
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
public protocol FeatureFlagSourceProviding {
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
