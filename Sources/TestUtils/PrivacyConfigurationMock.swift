//
//  PrivacyConfigurationMock.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

public final class PrivacyConfigurationMock: PrivacyConfiguration {

    public init() {}

    public var identifier: String = "id"
    public var version: String? = "123456789"

    public var userUnprotectedDomains: [String] = []

    public var tempUnprotectedDomains: [String] = []

    public var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist = .init(entries: [:],
                                                                            state: PrivacyConfigurationData.State.enabled)

    public var exceptionList: [PrivacyFeature: [String]] = [:]
    public func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] {
        return exceptionList[featureKey] ?? []
    }

    public var enabledFeatures: [PrivacyFeature: Set<String>] = [:]
    public func isFeature(_ feature: PrivacyFeature, enabledForDomain domain: String?) -> Bool {
        return enabledFeatures[feature]?.contains(domain ?? "") ?? false
    }

    public var enabledFeaturesForVersions: [PrivacyFeature: Set<String>] = [:]
    public func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> Bool {
        return enabledFeaturesForVersions[featureKey]?.contains(versionProvider.appVersion() ?? "") ?? false
    }

    public func stateFor(featureKey: BrowserServicesKit.PrivacyFeature, versionProvider: BrowserServicesKit.AppVersionProvider) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
        if isEnabled(featureKey: featureKey, versionProvider: versionProvider) {
            return .enabled
        }
        return .disabled(.disabledInConfig) // this is not used in platform tests, so mocking this poorly for now
    }

    public var enabledSubfeaturesForVersions: [String: Set<String>] = [:]
    public func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> Bool {
        return enabledSubfeaturesForVersions[subfeature.rawValue]?.contains(versionProvider.appVersion() ?? "") ?? false
    }

    public func stateFor(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        if isSubfeatureEnabled(subfeature, versionProvider: versionProvider, randomizer: randomizer) {
            return .enabled
        }
        return .disabled(.disabledInConfig) // this is not used in platform tests, so mocking this poorly for now
    }

    public var protectedDomains = Set<String>()
    public func isProtected(domain: String?) -> Bool {
        return protectedDomains.contains(domain ?? "")
    }

    public var tempUnprotected = Set<String>()
    public func isTempUnprotected(domain: String?) -> Bool {
        return tempUnprotected.contains(domain ?? "")
    }

    public func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool {
        return exceptionList[featureKey]?.contains(domain ?? "") ?? false
    }

    public var settings: [PrivacyFeature: PrivacyConfigurationData.PrivacyFeature.FeatureSettings] = [:]
    public func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        return settings[feature] ?? [:]
    }

    public func settings(for subfeature: any BrowserServicesKit.PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
        return nil
    }

    public var userUnprotected = Set<String>()
    public func userEnabledProtection(forDomain domain: String) {
        userUnprotected.remove(domain)
    }

    public func userDisabledProtection(forDomain domain: String) {
        userUnprotected.insert(domain)
    }

    public func isUserUnprotected(domain: String?) -> Bool {
        return userUnprotected.contains(domain ?? "")
    }

    public func stateFor(subfeatureID: BrowserServicesKit.SubfeatureID, parentFeatureID: BrowserServicesKit.ParentFeatureID, versionProvider: BrowserServicesKit.AppVersionProvider, randomizer: (Range<Double>) -> Double) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
        return .enabled
    }

    public func cohorts(for subfeature: any BrowserServicesKit.PrivacySubfeature) -> [BrowserServicesKit.PrivacyConfigurationData.Cohort]? {
        return nil
    }

    public func cohorts(subfeatureID: BrowserServicesKit.SubfeatureID, parentFeatureID: BrowserServicesKit.ParentFeatureID) -> [BrowserServicesKit.PrivacyConfigurationData.Cohort]? {
        return nil
    }

}
