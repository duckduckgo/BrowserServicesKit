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

public struct AppPrivacyConfiguration: PrivacyConfiguration {

    private(set) public var identifier: String
    
    private let data: PrivacyConfigurationData
    private let locallyUnprotected: DomainsProtectionStore

    public init(data: PrivacyConfigurationData,
                identifier: String,
                localProtection: DomainsProtectionStore) {
        self.data = data
        self.identifier = identifier
        self.locallyUnprotected = localProtection
    }

    public var userUnprotectedDomains: [String] {
        return Array(locallyUnprotected.unprotectedDomains).normalizedDomainsForContentBlocking()
    }
    
    public var tempUnprotectedDomains: [String] {
        return data.unprotectedTemporary.map { $0.domain }.normalizedDomainsForContentBlocking()
    }

    public var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlistData {
        return data.trackerAllowlist.state == PrivacyConfigurationData.State.enabled ? data.trackerAllowlist.entries : [:]
    }
    
    func parse(versionString: String) -> [Int] {
        return versionString.split(separator: ".").map { Int($0) ?? 0 }
    }
    
    func satisfiesMinVersion(feature: PrivacyConfigurationData.PrivacyFeature,
                             versionProvider: AppVersionProvider) -> Bool {
        if let minSupportedVersion = feature.minSupportedVersion,
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
        
        return satisfiesMinVersion(feature: feature, versionProvider: versionProvider)
                && feature.state == PrivacyConfigurationData.State.enabled
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

        let trimmedDomains = domainsList.filter { !$0.trimmingWhitespaces().isEmpty }

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
