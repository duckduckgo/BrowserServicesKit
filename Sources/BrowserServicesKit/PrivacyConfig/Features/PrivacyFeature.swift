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
    case newTabSearchField
    case dbp
    case sync
    case privacyDashboard
    case history
    case performanceMetrics
    case privacyPro
    case sslCertificates
    case brokenSiteReportExperiment
    case toggleReports
    case phishingDetection
    case brokenSitePrompt
    case remoteMessaging
    case additionalCampaignPixelParams
    case newTabPageImprovements
    case syncPromotion
    case autofillSurveys
    case marketplaceAdPostback
    case autocompleteTabs
    case networkProtection
    case aiChat
    case contextualOnboarding
    case textZoom
    case adAttributionReporting
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
    case onForExistingUsers
    case unknownUsernameCategorization
    case credentialsImportPromotionForExistingUsers
}

public enum DBPSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .dbp
    }

    case waitlist
    case waitlistBetaActive
    case freemium
}

public enum AIChatSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .aiChat
    }

    /// Displays the settings item for showing a shortcut in the Application Menu
    case applicationMenuShortcut

    /// Displays the settings item for showing a shortcut in the Toolbar
    case toolbarShortcut
}

public enum NetworkProtectionSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .networkProtection
    }

    /// Display user tips for Network Protection
    /// https://app.asana.com/0/72649045549333/1208231259093710/f
    case userTips
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
    case filterlistExperiment2
}

public enum PrivacyProSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .privacyPro }

    case isLaunched
    case isLaunchedStripe
    case allowPurchase
    case allowPurchaseStripe
    case isLaunchedOverride
    case isLaunchedOverrideStripe
    case useUnifiedFeedback
    case setAccessTokenCookieForSubscriptionDomains
}

public enum SslCertificatesSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .sslCertificates }
    case allowBypass
}

public enum DuckPlayerSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .duckPlayer }
    case pip
    case autoplay
    case openInNewTab
    case enableDuckPlayer // iOS DuckPlayer rollout feature
}

public enum PhishingDetectionSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .phishingDetection }
    case allowErrorPage
    case allowPreferencesToggle
}

public enum SyncPromotionSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .syncPromotion }
    case bookmarks
    case passwords
}
