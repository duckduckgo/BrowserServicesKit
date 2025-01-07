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

public protocol FlagCohort: RawRepresentable, CaseIterable where RawValue == CohortID {}

/// This protocol defines a common interface for feature flags managed by FeatureFlagger.
///
/// It should be implemented by the feature flag type in client apps.
///
public protocol FeatureFlagDescribing: CaseIterable {

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
    /// public enum FeatureFlag: FeatureFlagDescribing {
    ///    case sync
    ///    case autofill
    ///    case cookieConsent
    ///    case duckPlayer
    ///
    ///    var source: FeatureFlagSource {
    ///        case .sync:
    ///            return .disabled
    ///        case .cookieConsent:
    ///            return .internalOnly()
    ///        case .credentialsAutofill:
    ///            return .remoteDevelopment(.subfeature(AutofillSubfeature.credentialsAutofill))
    ///        case .duckPlayer:
    ///            return .remoteReleasable(.feature(.duckPlayer))
    ///    }
    /// }
    /// ```
    var source: FeatureFlagSource { get }
}

/// This protocol defines a common interface for experiment feature flags managed by FeatureFlagger.
///
/// It should be implemented by the feature flag type in client apps.
///
public protocol FeatureFlagExperimentDescribing {

    /// Returns a string representation of the flag
    var rawValue: String { get }

    /// Defines the source of the experiment feature flag, which corresponds to
    /// where the final flag value should come from.
    ///
    /// Example client implementation:
    ///
    /// ```
    /// public enum FeatureFlag: FeatureFlagDescribing {
    ///    case sync
    ///    case autofill
    ///    case cookieConsent
    ///    case duckPlayer
    ///
    ///    var source: FeatureFlagSource {
    ///        case .sync:
    ///            return .disabled
    ///        case .cookieConsent:
    ///            return .internalOnly(cohort)
    ///        case .credentialsAutofill:
    ///            return .remoteDevelopment(.subfeature(AutofillSubfeature.credentialsAutofill))
    ///        case .duckPlayer:
    ///            return .remoteReleasable(.feature(.duckPlayer))
    ///    }
    /// }
    /// ```
    var source: FeatureFlagSource { get }

    /// Represents the possible groups or variants within an experiment.
        ///
        /// The `Cohort` type is used to define user groups or test variations for feature
        /// experimentation. Each cohort typically corresponds to a specific behavior or configuration
        /// applied to a subset of users. For example, in an A/B test, you might define cohorts such as
        /// `control` and `treatment`.
        ///
        /// Each cohort must conform to the `CohortEnum` protocol, which ensures that the cohort type
        /// is an `enum` with `String` raw values and provides access to all possible cases
        /// through `CaseIterable`.
        ///
        /// Example:
        /// ```
        /// public enum AutofillCohorts: String, CohortEnum {
        ///     case control
        ///     case treatment
        /// }
        /// ```
        ///
        /// The `Cohort` type allows dynamic resolution of cohorts by their raw `String` value,
        /// making it easy to map user configurations to specific cohort groups.
    associatedtype CohortType: FlagCohort
}

public enum FeatureFlagSource {
    /// Completely disabled in all configurations
    case disabled

    /// Enabled for internal users only. Cannot be toggled remotely
    case internalOnly((any FlagCohort)? = nil)

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
    var localOverrides: FeatureFlagLocalOverriding? { get }

    /// Called from app features to determine whether a given feature is enabled.
    ///
    /// Feature Flag's `source` is checked to determine if the flag should be toggled.
    /// If feature flagger provides overrides mechanism (`localOverrides` is not `nil`)
    /// and the user is internal, local overrides is checked first and if present,
    /// returned as flag value.
    ///
    /// > Note: Setting `allowOverride` to `false` skips checking local overrides. This can be used
    ///   when the non-overridden feature flag value is required.
    ///
    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool

    /// Retrieves the cohort for a feature flag if the feature is enabled.
    ///
    /// This method determines the source of the feature flag and evaluates its eligibility based on
    /// the user's internal status and the privacy configuration. It supports different sources, such as
    /// disabled features, internal-only features, and remotely toggled features.
    ///
    /// - Parameter featureFlag: A feature flag conforming to `FeatureFlagDescribing`.
    ///
    /// - Returns: The `CohortID` associated with the feature flag, or `nil` if the feature is disabled or
    ///   does not meet the eligibility criteria.
    ///
    /// - Behavior:
    ///   - For `.disabled`: Returns `nil`.
    ///   - For `.internalOnly`: Returns the cohort if the user is an internal user.
    ///   - For `.remoteDevelopment` and `.remoteReleasable`:
    ///     - If the feature is a subfeature, resolves its cohort using `getCohortIfEnabled(_ subfeature:)`.
    ///     - Returns `nil` if the user is not eligible.
    ///
    func getCohortIfEnabled<Flag: FeatureFlagExperimentDescribing>(for featureFlag: Flag) -> (any FlagCohort)?

    /// Retrieves all active experiments currently assigned to the user.
    ///
    /// This method iterates over the experiments stored in the `ExperimentManager` and checks their state
    /// against the current `PrivacyConfiguration`. If an experiment's state is enabled or disabled due to
    /// a target mismatch, and its assigned cohort matches the resolved cohort, it is considered active.
    ///
    /// - Returns: A dictionary of active experiments where the key is the experiment's subfeature ID,
    ///   and the value is the associated `ExperimentData`.
    ///
    /// - Behavior:
    ///   1. Fetches all enrolled experiments from the `ExperimentManager`.
    ///   2. For each experiment:
    ///      - Retrieves its state from the `PrivacyConfiguration`.
    ///      - Validates its assigned cohort using `resolveCohort` in the `ExperimentManager`.
    ///   3. If the experiment passes validation, it is added to the result dictionary.
    ///
    func getAllActiveExperiments() -> Experiments
}

public extension FeatureFlagger {
    /// Called from app features to determine whether a given feature is enabled.
    ///
    /// Feature Flag's `source` is checked to determine if the flag should be toggled.
    /// If feature flagger provides overrides mechanism (`localOverrides` is not `nil`)
    /// and the user is internal, local overrides is checked first and if present,
    /// returned as flag value.
    ///
    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> Bool {
        isFeatureOn(for: featureFlag, allowOverride: true)
    }
}

public class DefaultFeatureFlagger: FeatureFlagger {

    public let internalUserDecider: InternalUserDecider
    public let privacyConfigManager: PrivacyConfigurationManaging
    private let experimentManager: ExperimentCohortsManaging?
    public let localOverrides: FeatureFlagLocalOverriding?

    public init(
        internalUserDecider: InternalUserDecider,
        privacyConfigManager: PrivacyConfigurationManaging,
        experimentManager: ExperimentCohortsManaging?
    ) {
        self.internalUserDecider = internalUserDecider
        self.privacyConfigManager = privacyConfigManager
        self.experimentManager = experimentManager
        self.localOverrides = nil
    }

    public init<Flag: FeatureFlagDescribing>(
        internalUserDecider: InternalUserDecider,
        privacyConfigManager: PrivacyConfigurationManaging,
        localOverrides: FeatureFlagLocalOverriding,
        experimentManager: ExperimentCohortsManaging?,
        for: Flag.Type
    ) {
        self.internalUserDecider = internalUserDecider
        self.privacyConfigManager = privacyConfigManager
        self.localOverrides = localOverrides
        self.experimentManager = experimentManager
        localOverrides.featureFlagger = self

        // Clear all overrides if not an internal user
        if !internalUserDecider.isInternalUser {
            localOverrides.clearAllOverrides(for: Flag.self)
        }
    }

    public func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
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

    public func getAllActiveExperiments() -> Experiments {
        guard let enrolledExperiments = experimentManager?.experiments else { return [:] }
        var activeExperiments = [String: ExperimentData]()
        let config = privacyConfigManager.privacyConfig

        for (subfeatureID, experimentData) in enrolledExperiments {
            let state = config.stateFor(subfeatureID: subfeatureID, parentFeatureID: experimentData.parentID)
            guard state == .enabled || state == .disabled(.targetDoesNotMatch) else { continue }
            let cohorts = config.cohorts(subfeatureID: subfeatureID, parentFeatureID: experimentData.parentID) ?? []
            let experimentSubfeature = ExperimentSubfeature(parentID: experimentData.parentID, subfeatureID: subfeatureID, cohorts: cohorts)

            if experimentManager?.resolveCohort(for: experimentSubfeature, allowCohortReassignment: false) == experimentData.cohortID {
                activeExperiments[subfeatureID] = experimentData
            }
        }
        return activeExperiments
    }

    public func getCohortIfEnabled<Flag: FeatureFlagExperimentDescribing>(for featureFlag: Flag) -> (any FlagCohort)? {
        switch featureFlag.source {
        case .disabled:
            return nil
        case .internalOnly(let cohort):
            return cohort
        case .remoteReleasable(let featureType),
                .remoteDevelopment(let featureType) where internalUserDecider.isInternalUser:
            if case .subfeature(let subfeature) = featureType {
                if let resolvedCohortID = getCohortIfEnabled(subfeature) {
                    return Flag.CohortType.allCases.first { return $0.rawValue == resolvedCohortID }
                }
            }
            return nil
        default:
            return nil
        }
    }

    private func getCohortIfEnabled(_ subfeature: any PrivacySubfeature) -> CohortID? {
        let config = privacyConfigManager.privacyConfig
        let featureState = config.stateFor(subfeature)
        let cohorts = config.cohorts(for: subfeature)
        let experiment = ExperimentSubfeature(parentID: subfeature.parent.rawValue, subfeatureID: subfeature.rawValue, cohorts: cohorts ?? [])
        switch featureState {
        case .enabled:
            return experimentManager?.resolveCohort(for: experiment, allowCohortReassignment: true)
        case .disabled(.targetDoesNotMatch):
            return experimentManager?.resolveCohort(for: experiment, allowCohortReassignment: false)
        default:
            return nil
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
