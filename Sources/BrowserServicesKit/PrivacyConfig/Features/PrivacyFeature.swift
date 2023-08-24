//
//  PrivacyFeature.swift
//  DuckDuckGo
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

/// Features whose `rawValue` should be the key to access their corresponding `PrivacyConfigurationData.PrivacyFeature` object
public enum PrivacyFeature: String {
    case contentBlocking
    case duckPlayer
    case fingerprintingTemporaryStorage
    case fingerprintingBattery
    case fingerprintingScreenSize
    case gpc
    case httpsUpgrade = "https"
    case autoconsent
    case clickToPlay
    case autofill
    case ampLinks
    case trackingParameters
    case customUserAgent
    case referrer
    case adClickAttribution
    case windowsWaitlist
    case windowsDownloadLink
    case incontextSignup
    case newTabContinueSetUp
    case incrementalRolloutTest // Temporary feature flag for testing incremental rollouts
}

/// An abstraction to be implemented by any "subfeature" of a given `PrivacyConfiguration` feature.
/// The `rawValue` should be the key to access their corresponding `PrivacyConfigurationData.PrivacyFeature.Feature` object
/// `parent` corresponds to the top level feature under which these subfeatures can be accessed
public protocol PrivacySubfeature: RawRepresentable where RawValue == String {
    var parent: PrivacyFeature { get }
}

// MARK: Subfeature definitions

public enum AutofillSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .autofill
    }

    case credentialsAutofill
    case credentialsSaving
    case inlineIconCredentials
    case accessCredentialManagement
    case autofillPasswordGeneration
}

public enum IncrementalRolloutTestSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .incrementalRolloutTest
    }

    case rollout
}
