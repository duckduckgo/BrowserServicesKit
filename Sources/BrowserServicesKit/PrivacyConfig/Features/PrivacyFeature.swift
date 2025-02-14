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
    case toggleReports
    case maliciousSiteProtection
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
    case experimentTest
    case forceOldAppDelegate
    case htmlNewTabPage
    case tabManager
    case webViewStateRestoration
}

/// An abstraction to be implemented by any "subfeature" of a given `PrivacyConfiguration` feature.
/// The `rawValue` should be the key to access their corresponding `PrivacyConfigurationData.PrivacyFeature.Feature` object
/// `parent` corresponds to the top level feature under which these subfeatures can be accessed
public protocol PrivacySubfeature: RawRepresentable where RawValue == String {
    var parent: PrivacyFeature { get }
}

// MARK: Subfeature definitions

public enum TabManagerSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .tabManager
    }

    case multiSelection
}

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
    case partialFormSaves
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

    /// Displays the settings item for showing a shortcut in the macOS application menu.
    case applicationMenuShortcut

    /// Displays the settings item for showing a shortcut in the macOS toolbar.
    case toolbarShortcut

    /// Displays the AI Chat icon in the iOS browsing menu toolbar.
    case browsingToolbarShortcut

    /// Displays the AI Chat icon in the iOS address bar while on a SERP.
    case addressBarShortcut

    /// Web and native integration for opening AI Chat in a custom webview.
    case deepLink
}

public enum NetworkProtectionSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .networkProtection
    }

    /// App Exclusions for the VPN
    /// https://app.asana.com/0/1206580121312550/1209150117333883/f
    case appExclusions

    /// Display user tips for Network Protection
    /// https://app.asana.com/0/72649045549333/1208231259093710/f
    case userTips

    /// Enforce routes for the VPN to fix TunnelVision
    /// https://app.asana.com/0/72649045549333/1208617860225199/f
    case enforceRoutes

    /// Risky Domain Protection for VPN
    /// https://app.asana.com/0/1204186595873227/1206489252288889
    case riskyDomainsProtection
}

public enum SyncSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .sync
    }

    case level0ShowSync
    case level1AllowDataSyncing
    case level2AllowSetupFlows
    case level3AllowCreateAccount
    case seamlessAccountSwitching
}

public enum AutoconsentSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .autoconsent
    }

    case onByDefault
    case filterlist
}

public enum PrivacyProSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .privacyPro }

    case allowPurchase
    case allowPurchaseStripe
    case useUnifiedFeedback
    case setAccessTokenCookieForSubscriptionDomains
    case privacyProFreeTrialJan25
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

public enum SyncPromotionSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .syncPromotion }
    case bookmarks
    case passwords
}

public enum ExperimentTestSubfeatures: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .experimentTest }
    case experimentTestAA
}

public enum HTMLNewTabPageSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .htmlNewTabPage }
    case isLaunched
}

public enum ContentBlockingSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .contentBlocking }
    case tdsNextExperimentBaseline
    case tdsNextExperimentFeb25
    case tdsNextExperimentMar25
    case tdsNextExperimentApr25
    case tdsNextExperimentMay25
    case tdsNextExperimentJun25
    case tdsNextExperimentJul25
    case tdsNextExperimentAug25
    case tdsNextExperimentSep25
    case tdsNextExperimentOct25
    case tdsNextExperimentNov25
    case tdsNextExperimentDec25
}

public enum MaliciousSiteProtectionSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .maliciousSiteProtection }
    case onByDefault // Rollout feature
}
