//
//  FeatureFlagLocalOverrides.swift
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

import Combine
import Foundation
import Persistence

/// This protocol defines persistence layer for feature flag overrides.
public protocol FeatureFlagLocalOverridesPersisting {
    /// Return value for the flag override.
    ///
    /// If there's no override, this function should return `nil`.
    ///
    func value<Flag: FeatureFlagDescribing>(for flag: Flag) -> Bool?
    func value<Flag: FeatureFlagExperimentDescribing>(for flag: Flag) -> CohortID?

    /// Set new override for the feature flag.
    ///
    /// Flag can be overridden to `true` or `false`. Setting `nil` clears the override.
    ///
    func set<Flag: FeatureFlagDescribing>(_ value: Bool?, for flag: Flag)
    func set<Flag: FeatureFlagExperimentDescribing>(_ value: CohortID?, for flag: Flag)
}

public struct FeatureFlagLocalOverridesUserDefaultsPersistor: FeatureFlagLocalOverridesPersisting {

    public let keyValueStore: KeyValueStoring

    public init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    public func value<Flag: FeatureFlagDescribing>(for flag: Flag) -> Bool? {
        let key = key(for: flag)
        return keyValueStore.object(forKey: key) as? Bool
    }

    public func value<Flag: FeatureFlagExperimentDescribing>(for flag: Flag) -> CohortID? {
        let key = key(for: flag)
        return keyValueStore.object(forKey: key) as? CohortID
    }

    public func set<Flag: FeatureFlagDescribing>(_ value: Bool?, for flag: Flag) {
        let key = key(for: flag)
        keyValueStore.set(value, forKey: key)
    }

    public func set<Flag: FeatureFlagExperimentDescribing>(_ value: CohortID?, for flag: Flag) {
        let key = key(for: flag)
        keyValueStore.set(value, forKey: key)
    }

    /// This function returns the User Defaults key for a feature flag override.
    ///
    /// It uses camel case to simplify inter-process User Defaults KVO.
    ///
    private func key<Flag: FeatureFlagDescribing>(for flag: Flag) -> String {
        return "localOverride\(flag.rawValue.capitalizedFirstLetter)"
    }

    private func key<Flag: FeatureFlagExperimentDescribing>(for flag: Flag) -> String {
        return "localOverride\(flag.rawValue.capitalizedFirstLetter)"
    }
}

private extension String {
    var capitalizedFirstLetter: String {
        return prefix(1).capitalized + dropFirst()
    }
}

/// This protocol defines the callback that can be used to reacting to feature flag changes.
public protocol FeatureFlagLocalOverridesHandling {

    /// This function is called whenever an effective value of a feature flag
    /// changes as a result of adding or removing a local override.
    ///
    /// It can be implemented by client apps to react to changes to feature flag
    /// value in runtime, caused by adjusting its local override.
    func flagDidChange<Flag: FeatureFlagDescribing>(_ featureFlag: Flag, isEnabled: Bool)
}

public protocol FeatureExperimentFlagLocalOverridesHandling {

    /// This function is called whenever an effective value of a feature flag
    /// changes as a result of adding or removing a local override.
    ///
    /// It can be implemented by client apps to react to changes to feature flag
    /// value in runtime, caused by adjusting its local override.
    func experimentFlagDidChange<Flag: FeatureFlagExperimentDescribing>(_ featureFlag: Flag, cohort: CohortID)
}

/// `FeatureFlagLocalOverridesHandling` implementation providing Combine publisher for flag changes.
///
/// It can be used by client apps if a more sophisticated handler isn't needed.
///
public struct FeatureFlagOverridesPublishingHandler<F: FeatureFlagDescribing>: FeatureFlagLocalOverridesHandling {

    public let flagDidChangePublisher: AnyPublisher<(F, Bool), Never>
    private let flagDidChangeSubject = PassthroughSubject<(F, Bool), Never>()

    public init() {
        flagDidChangePublisher = flagDidChangeSubject.eraseToAnyPublisher()
    }

    public func flagDidChange<Flag: FeatureFlagDescribing>(_ featureFlag: Flag, isEnabled: Bool) {
        guard let flag = featureFlag as? F else { return }
        flagDidChangeSubject.send((flag, isEnabled))
    }

}

public struct FeatureExperimentFlagOverridesPublishingHandler: FeatureExperimentFlagLocalOverridesHandling {

    public let experimentFlagDidChangePublisher: AnyPublisher<(any FeatureFlagExperimentDescribing, CohortID), Never>
    private let experimentFlagDidChangeSubject = PassthroughSubject<(any FeatureFlagExperimentDescribing, CohortID), Never>()

    public init() {
        experimentFlagDidChangePublisher = experimentFlagDidChangeSubject.eraseToAnyPublisher()
    }

    public func experimentFlagDidChange<Flag>(_ featureFlag: Flag, cohort: CohortID) where Flag : FeatureFlagExperimentDescribing {
        experimentFlagDidChangeSubject.send((featureFlag, cohort))
    }
}

/// This protocol defines the interface for feature flag overriding mechanism.
///
/// All flag overrides APIs only have effect if flag has `supportsLocalOverriding` set to `true`.
///
public protocol FeatureFlagLocalOverriding: AnyObject {

    /// Handle to the feature flagger.
    ///
    /// It's used to query current, non-overriden state of a feature flag to
    /// decide about calling `FeatureFlagLocalOverridesHandling.flagDidChange`
    /// upon clearing an override.
    var featureFlagger: FeatureFlagger? { get set }

    /// The action handler responding to feature flag changes.
    var featureActionHandler: FeatureFlagLocalOverridesHandling { get }

    /// The action handler responding to feature flag changes.
    var experimentActionHandler: FeatureExperimentFlagLocalOverridesHandling { get }

    /// Returns the current override for a feature flag, or `nil` if override is not set.
    func override<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> Bool?

    /// Returns the current override for a feature flag, or `nil` if override is not set.
    func override<Flag: FeatureFlagExperimentDescribing>(for featureFlag: Flag) -> CohortID?

    /// Toggles override for a feature flag.
    ///
    /// If override is not currently present, it sets the override to the opposite of the current flag value.
    ///
    func toggleOverride<Flag: FeatureFlagDescribing>(for featureFlag: Flag)
    func toggleExperimentCohort<Flag: FeatureFlagExperimentDescribing>(for featureFlag: Flag, cohort: CohortID)

    /// Clears override for a feature flag.
    ///
    /// Calls `FeatureFlagLocalOverridesHandling.flagDidChange` if the effective flag value
    /// changes as a result of clearing the override.
    ///
    func clearOverride<Flag: FeatureFlagDescribing>(for featureFlag: Flag)

    /// Clears overrides for all feature flags.
    ///
    /// This function calls `clearOverride(for:)` for each flag.
    ///
    func clearAllOverrides<Flag: FeatureFlagDescribing>(for flagType: Flag.Type)
}

public final class FeatureFlagLocalOverrides: FeatureFlagLocalOverriding {

    public var featureActionHandler: FeatureFlagLocalOverridesHandling
    public var experimentActionHandler: FeatureExperimentFlagLocalOverridesHandling
    public weak var featureFlagger: FeatureFlagger?
    private let persistor: FeatureFlagLocalOverridesPersisting

    public convenience init(
        keyValueStore: KeyValueStoring,
        featureActionHandler: FeatureFlagLocalOverridesHandling,
        experimentActionHandler: FeatureExperimentFlagLocalOverridesHandling
    ) {
        self.init(
            persistor: FeatureFlagLocalOverridesUserDefaultsPersistor(keyValueStore: keyValueStore),
            featureActionHandler: featureActionHandler,
            experimentActionHandler: experimentActionHandler
        )
    }

    public init(
        persistor: FeatureFlagLocalOverridesPersisting,
        featureActionHandler: FeatureFlagLocalOverridesHandling,
        experimentActionHandler: FeatureExperimentFlagLocalOverridesHandling
    ) {
        self.persistor = persistor
        self.featureActionHandler = featureActionHandler
        self.experimentActionHandler = experimentActionHandler
    }

    public func override<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> Bool? {
        guard featureFlag.supportsLocalOverriding else {
            return nil
        }
        return persistor.value(for: featureFlag)
    }

    public func override<Flag: FeatureFlagExperimentDescribing>(for featureFlag: Flag) -> CohortID? {
        guard featureFlag.supportsLocalOverriding else {
            return nil
        }
        return persistor.value(for: featureFlag)
    }

    public func toggleOverride<Flag: FeatureFlagDescribing>(for featureFlag: Flag) {
        guard featureFlag.supportsLocalOverriding else {
            return
        }
        let currentValue = persistor.value(for: featureFlag) ?? currentValue(for: featureFlag) ?? false
        let newValue = !currentValue
        persistor.set(newValue, for: featureFlag)
        featureActionHandler.flagDidChange(featureFlag, isEnabled: newValue)
    }

    public func toggleExperimentCohort<Flag: FeatureFlagExperimentDescribing>(for featureFlag: Flag, cohort: CohortID) {
        guard featureFlag.supportsLocalOverriding else {
            return
        }
        let newValue = cohort
        persistor.set(newValue, for: featureFlag)
        experimentActionHandler.experimentFlagDidChange(featureFlag, cohort: cohort)
    }

    public func clearOverride<Flag: FeatureFlagDescribing>(for featureFlag: Flag) {
        guard let override = override(for: featureFlag) else {
            return
        }
        persistor.set(nil, for: featureFlag)
        if let defaultValue = currentValue(for: featureFlag), defaultValue != override {
            featureActionHandler.flagDidChange(featureFlag, isEnabled: defaultValue)
        }
    }

    public func clearAllOverrides<Flag: FeatureFlagDescribing>(for flagType: Flag.Type) {
        flagType.allCases.forEach { flag in
            clearOverride(for: flag)
        }
    }

    private func currentValue<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> Bool? {
        featureFlagger?.isFeatureOn(for: featureFlag, allowOverride: true)
    }
}
