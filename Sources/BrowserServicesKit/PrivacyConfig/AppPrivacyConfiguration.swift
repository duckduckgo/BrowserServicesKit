//
//  AppPrivacyConfiguration.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Common

public struct AppPrivacyConfiguration: PrivacyConfiguration {
    
    private enum Constants {
        static let enabledKey = "enabled"
        static let lastRolloutCountKey = "lastRolloutCount"
    }

    private(set) public var identifier: String
    
    private let data: PrivacyConfigurationData
    private let locallyUnprotected: DomainsProtectionStore
    private let internalUserDecider: InternalUserDecider
    private let userDefaults: UserDefaults

    public init(data: PrivacyConfigurationData,
                identifier: String,
                localProtection: DomainsProtectionStore,
                internalUserDecider: InternalUserDecider,
                userDefaults: UserDefaults = UserDefaults()) {
        self.data = data
        self.identifier = identifier
        self.locallyUnprotected = localProtection
        self.internalUserDecider = internalUserDecider
        self.userDefaults = userDefaults
    }

    public var userUnprotectedDomains: [String] {
        return Array(locallyUnprotected.unprotectedDomains).normalizedDomainsForContentBlocking().sorted()
    }
    
    public var tempUnprotectedDomains: [String] {
        return data.unprotectedTemporary.map { $0.domain }.normalizedDomainsForContentBlocking()
    }

    public var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist {
        return data.trackerAllowlist
    }
    
    func parse(versionString: String) -> [Int] {
        return versionString.split(separator: ".").map { Int($0) ?? 0 }
    }
    
    func satisfiesMinVersion(_ version: String?,
                             versionProvider: AppVersionProvider) -> Bool {
        if let minSupportedVersion = version,
           let appVersion = versionProvider.appVersion() {
            let minVersion = parse(versionString: minSupportedVersion)
            let currentVersion = parse(versionString: appVersion)
            
            for i in 0..<max(minVersion.count, currentVersion.count) {
                let minSegment = i < minVersion.count ? minVersion[i] : 0
                let currSegment = i < currentVersion.count ? currentVersion[i] : 0
                
                if currSegment > minSegment {
                    return true
                }
                if currSegment < minSegment {
                    return false
                }
            }
        }
        
        return true
    }
    
    public func isEnabled(featureKey: PrivacyFeature,
                          versionProvider: AppVersionProvider = AppVersionProvider()) -> Bool {
        guard let feature = data.features[featureKey.rawValue] else { return false }

        let satisfiesMinVersion = satisfiesMinVersion(feature.minSupportedVersion, versionProvider: versionProvider)
        switch feature.state {
        case PrivacyConfigurationData.State.enabled: return satisfiesMinVersion
        case PrivacyConfigurationData.State.internal: return internalUserDecider.isInternalUser && satisfiesMinVersion
        default: return false
        }
    }
    
    private func isRolloutEnabled(subfeature: any PrivacySubfeature,
                                  rolloutSteps: [PrivacyConfigurationData.PrivacyFeature.Feature.RolloutStep],
                                  randomizer: (Range<Double>) -> Double) -> Bool {
        // Empty rollouts should be default enabled
        guard !rolloutSteps.isEmpty else { return true }
        
        let defsPrefix = "config.\(subfeature.parent.rawValue).\(subfeature.rawValue)"
        if userDefaults.bool(forKey: "\(defsPrefix).\(Constants.enabledKey)") {
            return true
        }
        
        var willEnable = false
        let rollouts = Array(Set(rolloutSteps.filter({ $0.percent >= 0.0 && $0.percent <= 100.0 }))).sorted(by: { $0.percent < $1.percent })
        if let rolloutSize = userDefaults.value(forKey: "\(defsPrefix).\(Constants.lastRolloutCountKey)") as? Int {
            guard rolloutSize < rollouts.count else { return false }
            // Sanity check as we need at least two values to compute the new probability
            guard rollouts.count > 1 else { return false }
            
            // If the user has seen the rollout before, and the rollout count has changed
            // Try again with the new probability
            let y = rollouts[rollouts.count - 1].percent
            let x = rollouts[rollouts.count - 2].percent
            let prob = (y - x) / (100.0 - x)
            if randomizer(0..<1) < prob {
                // enable the feature
                willEnable = true
            }
        } else {
            // First time user sees feature
            let probability = (rollouts.count > 1 ? rollouts.last?.percent : rollouts.first?.percent) ?? 0.0
            willEnable = randomizer(0..<100) < probability
        }
        
        guard willEnable else {
            userDefaults.set(rollouts.count, forKey: "\(defsPrefix).\(Constants.lastRolloutCountKey)")
            return false
        }
        
        userDefaults.set(true, forKey: "\(defsPrefix).\(Constants.enabledKey)")
        return true
    }

    public func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature,
                                    versionProvider: AppVersionProvider,
                                    randomizer: (Range<Double>) -> Double) -> Bool {
        guard isEnabled(featureKey: subfeature.parent, versionProvider: versionProvider) else {
            return false
        }
        let subfeatures = subfeatures(for: subfeature.parent)
        let subfeatureData = subfeatures[subfeature.rawValue]
        let satisfiesMinVersion = satisfiesMinVersion(subfeatureData?.minSupportedVersion, versionProvider: versionProvider)
        
        // Handle Rollouts
        if let rollout = subfeatureData?.rollout {
            if !isRolloutEnabled(subfeature: subfeature, rolloutSteps: rollout.steps, randomizer: randomizer) {
                return false
            }
        }
        
        switch subfeatureData?.state {
        case PrivacyConfigurationData.State.enabled: return satisfiesMinVersion
        case PrivacyConfigurationData.State.internal: return internalUserDecider.isInternalUser && satisfiesMinVersion
        default: return false
        }
    }

    private func subfeatures(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.Features {
        return data.features[feature.rawValue]?.features ?? [:]
    }
    
    public func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] {
        guard let feature = data.features[featureKey.rawValue] else { return [] }
        
        return feature.exceptions.map { $0.domain }.normalizedDomainsForContentBlocking()
    }

    public func isFeature(_ feature: PrivacyFeature, enabledForDomain domain: String?) -> Bool {
        guard isEnabled(featureKey: feature) else {
            return false
        }

        if let domain = domain,
           isTempUnprotected(domain: domain) ||
            isUserUnprotected(domain: domain) ||
            isInExceptionList(domain: domain, forFeature: feature) {
            return false
        }
        return true
    }

    public func isProtected(domain: String?) -> Bool {
        guard let domain = domain else { return true }

        return !isTempUnprotected(domain: domain) && !isUserUnprotected(domain: domain) &&
            !isInExceptionList(domain: domain, forFeature: .contentBlocking)
    }

    public func isUserUnprotected(domain: String?) -> Bool {
        guard let domain = domain else { return false }

        return userUnprotectedDomains.contains(domain)
    }

    public func isTempUnprotected(domain: String?) -> Bool {
        return isDomain(domain, wildcardMatching: tempUnprotectedDomains)
    }

    public func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool {
        return isDomain(domain, wildcardMatching: exceptionsList(forFeature: featureKey))
    }

    private func isDomain(_ domain: String?, wildcardMatching domainsList: [String]) -> Bool {
        guard let domain = domain else { return false }

        let trimmedDomains = domainsList.filter { !$0.trimmingWhitespace().isEmpty }

        // Break domain apart to handle www.*
        var tempDomain = domain
        while tempDomain.contains(".") {
            if trimmedDomains.contains(tempDomain) {
                return true
            }

            let comps = tempDomain.split(separator: ".")
            tempDomain = comps.dropFirst().joined(separator: ".")
        }

        return false
    }

    public func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        return data.features[feature.rawValue]?.settings ?? [:]
    }

    public func userEnabledProtection(forDomain domain: String) {
        let domainToRemove = locallyUnprotected.unprotectedDomains.first { unprotectedDomain in
            unprotectedDomain.punycodeEncodedHostname.lowercased() == domain
        }
        locallyUnprotected.enableProtection(forDomain: domainToRemove ?? domain)
    }

    public func userDisabledProtection(forDomain domain: String) {
        locallyUnprotected.disableProtection(forDomain: domain.punycodeEncodedHostname.lowercased())
    }
    
}

extension Array where Element == String {
    
    func normalizedDomainsForContentBlocking() -> [String] {
        map { domain in
            domain.punycodeEncodedHostname.lowercased()
        }
    }
}
