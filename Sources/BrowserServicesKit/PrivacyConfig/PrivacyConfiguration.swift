//
//  PrivacyConfiguration.swift
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

public protocol PrivacyConfiguration {

    /// Identifier of given Privacy Configuration, typically an ETag
    var identifier: String { get }

    /// Domains for which user has toggled protection off.
    ///
    /// Use `isUserUnprotected(domain:)` to check if given domain is unprotected.
    var userUnprotectedDomains: [String] { get }

    /// Domains for which all protections has been disabled because of some broken functionality
    ///
    /// Use `isTempUnprotected(domain:)` to check if given domain is unprotected.
    var tempUnprotectedDomains: [String] { get }

    /// Trackers that has been allow listed because of site breakage
    var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlistData { get }

    func isEnabled(featureKey: PrivacyFeature) -> Bool

    /// Domains for which given PrivacyFeature is disabled.
    ///
    /// Use `isTempUnprotected(domain:)` to check if a feature is disabled for the given domain.
    func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String]

    /// Check the protection status of given domain.
    ///
    /// Returns true if all below is true:
    ///  - Site is not user unprotected.
    ///  - Site is not in temp list.
    ///  - Site is not in an exception list for content blocking feature.
    func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool

    /// Check the protection status of given domain.
    ///
    /// Returns true if all below is true:
    ///  - Site is not user unprotected.
    ///  - Site is not in temp list.
    ///  - Site is not in an exception list for content blocking feature.
    func isProtected(domain: String?) -> Bool

    /// Check if given domain is locally unprotected.
    ///
    /// Returns true for exact match, but false for subdomains.
    func isUserUnprotected(domain: String?) -> Bool

    /// Check if given domain is temp unprotected.
    ///
    /// Returns true for exact match and all subdomains.
    func isTempUnprotected(domain: String?) -> Bool

    /// Check if given domain is in exception list.
    ///
    /// Returns true for exact match and all subdomains.
    func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool

    /// Returns settings for a specified feature.
    func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings

    /// Removes given domain from locally unprotected list.
    func userEnabledProtection(forDomain: String)
    /// Adds given domain to locally unprotected list.
    func userDisabledProtection(forDomain: String)
}

public enum PrivacyFeature: String {
    case contentBlocking
    case fingerprintingTemporaryStorage
    case fingerprintingBattery
    case fingerprintingScreenSize
    case gpc
    case httpsUpgrade = "https"
    case autoconsent
}
