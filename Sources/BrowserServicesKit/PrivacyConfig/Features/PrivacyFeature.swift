//
//  PrivacyFeature.swift
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
    case clickToLoad
    case autofill
    case autofillBreakageReporter
    case ampLinks
    case trackingParameters
    case customUserAgent
    case referrer
    case adClickAttribution
    case windowsWaitlist
    case windowsDownloadLink
    case incontextSignup
    case newTabContinueSetUp
    case dbp
    case sync
    case privacyDashboard
    case history
    case performanceMetrics
    case privacyPro
    case sslCertificates
    case brokenSiteReportExperiment
    case toggleReports
    case remoteMessaging
    case additionalCampaignPixelParams
    case backgroundAgentPixelTest
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
    case onByDefault
    case deduplicateLoginsOnImport
    case onForExistingUsers
}

public enum DBPSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .dbp
    }

    case waitlist
    case waitlistBetaActive
}

public enum SyncSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .sync
    }

    case level0ShowSync
    case level1AllowDataSyncing
    case level2AllowSetupFlows
    case level3AllowCreateAccount
}

public enum AutoconsentSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .autoconsent
    }

    case onByDefault
}

public enum PrivacyProSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .privacyPro }

    case isLaunched
    case isLaunchedStripe
    case allowPurchase
    case allowPurchaseStripe
    case isLaunchedOverride
    case isLaunchedOverrideStripe
}

public enum sslCertificatesSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .sslCertificates }
    case allowBypass
}

public enum DuckPlayerSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .duckPlayer }
    case pip
    case autoplay
    case openInNewTab
}

public enum BackgroundAgentPixelTestSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .backgroundAgentPixelTest }
    case pixelTest
}
