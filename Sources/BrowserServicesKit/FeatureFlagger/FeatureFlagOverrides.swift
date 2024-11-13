//
//  FeatureFlagOverrides.swift
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
import Persistence

/// This protocol defines persistence layer for feature flag overrides.
public protocol FeatureFlagOverridesPersistor {
    /// Return value for the flag override.
    ///
    /// If there's no override, this function should return `nil`.
    ///
    func value<Flag: FeatureFlagProtocol>(for flag: Flag) -> Bool?

    /// Set new override for the feature flag.
    ///
    /// Flag can be overridden to `true` or `false`. Setting `nil` clears the override.
    ///
    func set<Flag: FeatureFlagProtocol>(_ value: Bool?, for flag: Flag)
}

public struct FeatureFlagOverridesUserDefaultsPersistor: FeatureFlagOverridesPersistor {

    public let keyValueStore: KeyValueStoring

    public init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    public func value<Flag: FeatureFlagProtocol>(for flag: Flag) -> Bool? {
        let key = key(for: flag)
        return keyValueStore.object(forKey: key) as? Bool
    }

    public func set<Flag: FeatureFlagProtocol>(_ value: Bool?, for flag: Flag) {
        let key = key(for: flag)
        keyValueStore.set(value, forKey: key)
    }

    /// This function returns the User Defaults key for a feature flag override.
    ///
    /// It uses camel case to allow inter-process User Defaults KVO.
    ///
    private func key<Flag: FeatureFlagProtocol>(for flag: Flag) -> String {
        return "localOverride\(flag.rawValue.capitalizedFirstLetter)"
    }
}

private extension String {
    var capitalizedFirstLetter: String {
        return prefix(1).capitalized + dropFirst()
    }
}

/// This protocol defines the callback that can be used to reacting to feature flag changes.
public protocol FeatureFlagOverridesHandler {

    /// This function is called whenever an effective value of a feature flag
    /// changes as a result of adding or removing a local override.
    ///
    /// It can be implemented by client apps to react to changes to feature flag
    /// value in runtime, caused by adjusting its local override.
    func flagDidChange<Flag: FeatureFlagProtocol>(_ featureFlag: Flag, isEnabled: Bool)
}

/// This protocol defines the interface for feature flag overriding mechanism.
///
/// All flag overrides APIs only have effect if flag has `supportsLocalOverriding` set to `true`.
///
public protocol FeatureFlagOverriding: AnyObject {

    /// Handle to the feature flagged.
    ///
    /// It's used to query current, non-overriden state of a feature flag to
    /// decide about calling `FeatureFlagOverridesHandler.flagDidChange`
    /// upon clearing an override.
    var featureFlagger: FeatureFlagger? { get set }

    /// Returns the current override for a feature flag, or `nil` if override is not set.
    func override<Flag: FeatureFlagProtocol>(for featureFlag: Flag) -> Bool?

    /// Toggles override for a feature flag.
    ///
    /// If override is not currently present, it sets the override to the opposite of the current flag value.
    ///
    func toggleOverride<Flag: FeatureFlagProtocol>(for featureFlag: Flag)

    /// Clears override for a feature flag.
    ///
    /// Calls `FeatureFlagOverridesHandler.flagDidChange` if the effective flag value
    /// changes as a result of clearing the override.
    ///
    func clearOverride<Flag: FeatureFlagProtocol>(for featureFlag: Flag)

    /// Clears overrides for all feature flags.
    ///
    /// This function calls `clearOverride(for:)` for each flag.
    ///
    func clearAllOverrides<Flag: FeatureFlagProtocol>(for flagType: Flag.Type)
}

public final class FeatureFlagOverrides: FeatureFlagOverriding {

    private var persistor: FeatureFlagOverridesPersistor
    private var actionHandler: FeatureFlagOverridesHandler
    public weak var featureFlagger: FeatureFlagger?

    public convenience init(
        keyValueStore: KeyValueStoring,
        actionHandler: FeatureFlagOverridesHandler
    ) {
        self.init(
            persistor: FeatureFlagOverridesUserDefaultsPersistor(keyValueStore: keyValueStore),
            actionHandler: actionHandler
        )
    }

    public init(
        persistor: FeatureFlagOverridesPersistor,
        actionHandler: FeatureFlagOverridesHandler
    ) {
        self.persistor = persistor
        self.actionHandler = actionHandler
    }

    public func override<Flag: FeatureFlagProtocol>(for featureFlag: Flag) -> Bool? {
        guard featureFlag.supportsLocalOverriding else {
            return nil
        }
        return persistor.value(for: featureFlag)
    }

    public func toggleOverride<Flag: FeatureFlagProtocol>(for featureFlag: Flag) {
        guard featureFlag.supportsLocalOverriding else {
            return
        }
        let currentValue = persistor.value(for: featureFlag) ?? currentValue(for: featureFlag) ?? false
        let newValue = !currentValue
        persistor.set(newValue, for: featureFlag)
        actionHandler.flagDidChange(featureFlag, isEnabled: newValue)
    }

    public func clearOverride<Flag: FeatureFlagProtocol>(for featureFlag: Flag) {
        guard let override = override(for: featureFlag) else {
            return
        }
        persistor.set(nil, for: featureFlag)
        if let defaultValue = currentValue(for: featureFlag), defaultValue != override {
            actionHandler.flagDidChange(featureFlag, isEnabled: defaultValue)
        }
    }

    public func clearAllOverrides<Flag: FeatureFlagProtocol>(for flagType: Flag.Type) {
        flagType.allCases.forEach { flag in
            clearOverride(for: flag)
        }
    }

    private func currentValue<Flag: FeatureFlagProtocol>(for featureFlag: Flag) -> Bool? {
        featureFlagger?.isFeatureOn(for: featureFlag, allowOverride: true)
    }
}
