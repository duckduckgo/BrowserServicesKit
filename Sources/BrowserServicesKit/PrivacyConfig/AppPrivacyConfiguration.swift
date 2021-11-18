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
        return Array(locallyUnprotected.unprotectedDomains)
    }
    
    public var tempUnprotectedDomains: [String] {
        return data.unprotectedTemporary.map { $0.domain }
    }

    public var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlistData {
        return data.trackerAllowlist.state == PrivacyConfigurationData.State.enabled ? data.trackerAllowlist.entries : [:]
    }
    
    public func isEnabled(featureKey: PrivacyFeature) -> Bool {
        guard let feature = data.features[featureKey.rawValue] else { return false }
        
        return feature.state == PrivacyConfigurationData.State.enabled
    }
    
    public func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] {
        guard let feature = data.features[featureKey.rawValue] else { return [] }
        
        return feature.exceptions.map { $0.domain }
    }

    public func isProtected(domain: String?) -> Bool {
        guard let domain = domain else { return true }

        return !isTempUnprotected(domain: domain) && !isUserUnprotected(domain: domain) &&
            !isInExceptionList(domain: domain, forFeature: .contentBlocking)
    }

    public func isUserUnprotected(domain: String?) -> Bool {
        guard let domain = domain else { return false }

        return locallyUnprotected.unprotectedDomains.contains(domain)
    }

    public func isTempUnprotected(domain: String?) -> Bool {
        return isDomain(domain, wildcardMatching: tempUnprotectedDomains)
    }

    public func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool {
        return isDomain(domain, wildcardMatching: exceptionsList(forFeature: featureKey))
    }

    private func isDomain(_ domain: String?, wildcardMatching domainsList: [String]) -> Bool {
        guard let domain = domain else { return false }

        let trimmedDomains = domainsList.filter { !$0.trimWhitespace().isEmpty }

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

    public func userEnabledProtection(forDomain domain: String) {
        locallyUnprotected.enableProtection(forDomain: domain)
    }

    public func userDisabledProtection(forDomain domain: String) {
        locallyUnprotected.disableProtection(forDomain: domain)
    }
    
}
