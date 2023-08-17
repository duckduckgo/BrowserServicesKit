//
//  AppPrivacyConfigurationTests.swift
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

import XCTest
import BrowserServicesKit

class MockEmbeddedDataProvider: EmbeddedDataProvider {
    var embeddedDataEtag: String

    var embeddedData: Data

    init(data: Data, etag: String) {
        embeddedData = data
        embeddedDataEtag = etag
    }
}

class MockAppVersionProvider: AppVersionProvider {
    var mockedVersion: String

    override func appVersion() -> String {
        return mockedVersion
    }

    init(appVersion: String) {
        self.mockedVersion = appVersion
    }
}

class AppPrivacyConfigurationTests: XCTestCase {

    let embeddedConfig =
    """
    {
        "features": {},
        "unprotectedTemporary": [
                { "domain": "domain1.com" },
                { "domain": "domain2.com" },
                { "domain": "domain3.com" },
        ]
    }
    """.data(using: .utf8)!
    let embeddedConfigETag = "embedded"

    let downloadedConfig =
    """
    {
        "features": {},
        "unprotectedTemporary": [
                { "domain": "domain1.com" },
                { "domain": "domain5.com" },
                { "domain": "domain6.com" },
        ]
    }
    """.data(using: .utf8)!
    let downloadedConfigETag = "downloaded"

    let corruptedConfig =
    """
    {
        "features": {},
        "unprotectedTemporary": [
    }
    """.data(using: .utf8)!
    let corruptedConfigETag = "corrupted"

    func testWhenDownloadedDataIsMissing_ThenEmbeddedIsUsed() {

        let mockEmbeddedData = MockEmbeddedDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedDataEtag)
        XCTAssertEqual(manager.reload(etag: nil, data: nil), PrivacyConfigurationManager.ReloadResult.embedded)

        XCTAssertNil(manager.fetchedConfigData)

        let config = manager.privacyConfig
        XCTAssertFalse(config.isTempUnprotected(domain: "main1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "notdomain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain5.com"))

        XCTAssertTrue(config.isTempUnprotected(domain: "www.domain1.com"))
    }

    func testWhenDataIsPresent_ThenItIsUsed() {

        let mockEmbeddedData = MockEmbeddedDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: downloadedConfigETag,
                                                  fetchedData: downloadedConfig,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedDataEtag)
        XCTAssertEqual(manager.fetchedConfigData?.etag, downloadedConfigETag)

        let config = manager.privacyConfig
        XCTAssertFalse(config.isTempUnprotected(domain: "main1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "notdomain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain5.com"))

        XCTAssertTrue(config.isTempUnprotected(domain: "www.domain1.com"))
    }

    func testWhenDownloadedDataIsReloaded_ThenItIsUsed() {

        let mockEmbeddedData = MockEmbeddedDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedDataEtag)
        XCTAssertNil(manager.fetchedConfigData)

        XCTAssertEqual(manager.reload(etag: downloadedConfigETag, data: downloadedConfig), .downloaded)

        let config = manager.privacyConfig
        XCTAssertFalse(config.isTempUnprotected(domain: "main1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "notdomain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain5.com"))

        XCTAssertTrue(config.isTempUnprotected(domain: "www.domain1.com"))
    }

    func testWhenPresentDataIsCorrupted_ThenEmbeddedIsUsed() {

        let mockEmbeddedData = MockEmbeddedDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: corruptedConfigETag,
                                                  fetchedData: corruptedConfig,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedDataEtag)
        XCTAssertNil(manager.fetchedConfigData)

        // Should use embedded
        var config = manager.privacyConfig
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain5.com"))

        // Attempt fix
        XCTAssertEqual(manager.reload(etag: downloadedConfigETag, data: downloadedConfig), .downloaded)

        config = manager.privacyConfig
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain5.com"))
    }

    func testWhenReloadedDataIsCorrupted_ThenEmbeddedIsUsed() {

        let mockEmbeddedData = MockEmbeddedDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedDataEtag)
        XCTAssertNil(manager.fetchedConfigData)

        // Should use embedded
        var config = manager.privacyConfig
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain5.com"))

        // Attempt fix
        XCTAssertEqual(manager.reload(etag: corruptedConfigETag, data: corruptedConfig), .embeddedFallback)

        config = manager.privacyConfig
        XCTAssertTrue(config.isTempUnprotected(domain: "domain1.com"))
        XCTAssertTrue(config.isTempUnprotected(domain: "domain2.com"))
        XCTAssertFalse(config.isTempUnprotected(domain: "domain5.com"))
    }

    func testWhenCheckingUnprotectedSites_ThenProtectionStoreIsUsed() {

        let mockEmbeddedData = MockEmbeddedDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let mockProtectionStore = MockDomainsProtectionStore()
        mockProtectionStore.disableProtection(forDomain: "enabled.com")

        let manager = PrivacyConfigurationManager(fetchedETag: corruptedConfigETag,
                                                  fetchedData: corruptedConfig,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore,
                                                  internalUserDecider: DefaultInternalUserDecider())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedDataEtag)
        XCTAssertNil(manager.fetchedConfigData)

        let config = manager.privacyConfig

        XCTAssertTrue(config.isUserUnprotected(domain: "enabled.com"))

        config.userDisabledProtection(forDomain: "enabled2.com")
        XCTAssertTrue(config.isUserUnprotected(domain: "enabled2.com"))
    }

    func testWhenRequestingUnprotectedSites_ThenTheyAreConsistentlyOrdered() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: embeddedConfig, etag: embeddedConfigETag)

        let mockProtectionStore = MockDomainsProtectionStore()

        let manager = PrivacyConfigurationManager(fetchedETag: corruptedConfigETag,
                                                  fetchedData: corruptedConfig,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore,
                                                  internalUserDecider: DefaultInternalUserDecider())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedDataEtag)
        XCTAssertNil(manager.fetchedConfigData)

        let config = manager.privacyConfig

        mockProtectionStore.unprotectedDomains = ["first.com", "second.com"]
        XCTAssertEqual(config.userUnprotectedDomains, ["first.com", "second.com"])

        mockProtectionStore.unprotectedDomains = ["second.com", "first.com"]
        XCTAssertEqual(config.userUnprotectedDomains, ["first.com", "second.com"])
    }

    let exampleConfig =
    """
    {
        "features": {
            "gpc": {
                "state": "enabled",
                "exceptions": [
                    {
                        "domain": "example.com",
                        "reason": "site breakage"
                    }
                ]
            }
        },
        "unprotectedTemporary": [
            {
                "domain": "unp.com",
                "reason": "site breakage"
            }
        ]
    }
    """.data(using: .utf8)!

    func testWhenCheckingFeatureState_ThenValidStateIsReturned() {

        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleConfig, etag: "test")

        let mockProtectionStore = MockDomainsProtectionStore()
        mockProtectionStore.disableProtection(forDomain: "disabled.com")

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore,
                                                  internalUserDecider: DefaultInternalUserDecider())

        XCTAssertEqual(manager.embeddedConfigData.etag, mockEmbeddedData.embeddedDataEtag)
        XCTAssertNil(manager.fetchedConfigData)

        let config = manager.privacyConfig

        XCTAssertTrue(config.isFeature(.gpc, enabledForDomain: nil))
        XCTAssertTrue(config.isFeature(.gpc, enabledForDomain: "test.com"))
        XCTAssertFalse(config.isFeature(.gpc, enabledForDomain: "disabled.com"))
        XCTAssertFalse(config.isFeature(.gpc, enabledForDomain: "example.com"))
        XCTAssertFalse(config.isFeature(.gpc, enabledForDomain: "unp.com"))
    }

    let exampleVersionConfig =
    """
    {
        "features": {
            "gpc": {
                "state": "enabled",
                "exceptions": [
                    {
                        "domain": "example.com",
                        "reason": "site breakage"
                    }
                ]
            },
            "trackingParameters": {
                "state": "enabled",
                "minSupportedVersion": "0.22.2",
                "exceptions": []
            },
            "ampLinks": {
                "state": "enabled",
                "minSupportedVersion": "7.66.1.0",
                "exceptions": []
            }
        },
        "unprotectedTemporary": [
            {
                "domain": "unp.com",
                "reason": "site breakage"
            }
        ]
    }
    """.data(using: .utf8)!

    func testMinSupportedVersionCheckReturnsCorrectly() {
        var appVersion = MockAppVersionProvider(appVersion: "0.22.2")

        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleVersionConfig, etag: "test")
        let mockProtectionStore = MockDomainsProtectionStore()

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: mockProtectionStore,
                                                  internalUserDecider: DefaultInternalUserDecider())

        let config = manager.privacyConfig

        XCTAssertTrue(config.isEnabled(featureKey: .gpc, versionProvider: appVersion))
        XCTAssertTrue(config.isEnabled(featureKey: .trackingParameters, versionProvider: appVersion))

        appVersion = MockAppVersionProvider(appVersion: "0.22.3")
        XCTAssertTrue(config.isEnabled(featureKey: .trackingParameters, versionProvider: appVersion))
        appVersion = MockAppVersionProvider(appVersion: "1.0.0")
        XCTAssertTrue(config.isEnabled(featureKey: .trackingParameters, versionProvider: appVersion))
        appVersion = MockAppVersionProvider(appVersion: "1.0.0.0")
        XCTAssertTrue(config.isEnabled(featureKey: .trackingParameters, versionProvider: appVersion))

        // Test invalid version format
        XCTAssertFalse(config.isEnabled(featureKey: .ampLinks, versionProvider: appVersion))

        // Test unsupported version
        appVersion = MockAppVersionProvider(appVersion: "0.22.0")
        XCTAssertFalse(config.isEnabled(featureKey: .trackingParameters, versionProvider: appVersion))
        appVersion = MockAppVersionProvider(appVersion: "7.65.1.0")
        XCTAssertFalse(config.isEnabled(featureKey: .ampLinks, versionProvider: appVersion))
    }

    let exampleInternalConfig =
    """
    {
        "features": {
            "gpc": {
                "state": "internal",
                "exceptions": []
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!

    func testWhenCheckingFeatureState_WhenInternal_ThenValidStateIsReturned() {

        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleInternalConfig, etag: "test")
        let mockInternalUserStore = MockInternalUserStoring()

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider(store: mockInternalUserStore))
        let config = manager.privacyConfig

        mockInternalUserStore.isInternalUser = true
        XCTAssertTrue(config.isEnabled(featureKey: .gpc))
        mockInternalUserStore.isInternalUser = false
        XCTAssertFalse(config.isEnabled(featureKey: .gpc))
    }

    let exampleSubfeaturesConfig =
    """
    {
        "features": {
            "autofill": {
                "state": "enabled",
                "exceptions": [],
                "features": {
                    "credentialsAutofill": {
                        "state": "disabled"
                    },
                    "credentialsSaving": {
                        "state": "enabled",
                        "minSupportedVersion": "1.36.0"
                    },
                    "inlineIconCredentials": {
                        "state": "enabled"
                    },
                    "accessCredentialManagement": {
                        "state": "internal"
                    }
                },
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!

    func testWhenCheckingSubfeatureState_ThenValidStateIsReturned() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleSubfeaturesConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let config = manager.privacyConfig

        XCTAssertFalse(config.isSubfeatureEnabled(AutofillSubfeature.credentialsAutofill))
        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.inlineIconCredentials))
    }

    func testWhenCheckingSubfeatureState_WhenInternalUser_ThenValidStateIsReturnedForInternalFeatures() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleSubfeaturesConfig, etag: "test")
        let mockInternalUserStore = MockInternalUserStoring()

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider(store: mockInternalUserStore))
        let config = manager.privacyConfig

        mockInternalUserStore.isInternalUser = true
        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.accessCredentialManagement))
        mockInternalUserStore.isInternalUser = false
        XCTAssertFalse(config.isSubfeatureEnabled(AutofillSubfeature.accessCredentialManagement))
    }

    func testWhenCheckingSubfeatureState_MinSupportedVersionCheckReturnsCorrectly() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleSubfeaturesConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let config = manager.privacyConfig

        let oldVersionProvider = MockAppVersionProvider(appVersion: "1.35.0")
        XCTAssertFalse(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, versionProvider: oldVersionProvider, randomizer: Double.random(in:)))
        let currentVersionProvider = MockAppVersionProvider(appVersion: "1.36.0")
        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, versionProvider: currentVersionProvider, randomizer: Double.random(in:)))
        let futureVersionProvider = MockAppVersionProvider(appVersion: "2.16.0")
        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, versionProvider: futureVersionProvider, randomizer: Double.random(in:)))
    }

    let exampleDisabledFeatureStateOverridingSubfeatureConfig =
    """
    {
        "features": {
            "autofill": {
                "state": "disabled",
                "exceptions": [],
                "features": {
                    "credentialsAutofill": {
                        "state": "enabled"
                    }
                },
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!

    func testWhenCheckingSubfeatureState_DisabledParentFeatureStateOverridesSubfeature() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleDisabledFeatureStateOverridingSubfeatureConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let config = manager.privacyConfig

        XCTAssertFalse(config.isEnabled(featureKey: .autofill))
        XCTAssertFalse(config.isSubfeatureEnabled(AutofillSubfeature.credentialsAutofill))
    }

    let exampleDisabledFeatureMinVersionOverridingSubfeatureConfig =
    """
    {
        "features": {
            "autofill": {
                "state": "enabled",
                "minSupportedVersion": "1.36.0",
                "exceptions": [],
                "features": {
                    "credentialsSaving": {
                        "state": "enabled",
                        "minSupportedVersion": "1.35.0"
                    }
                },
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!

    func testWhenCheckingSubfeatureState_DisabledParentFeatureVersionOverridesSubfeature() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleDisabledFeatureMinVersionOverridingSubfeatureConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let config = manager.privacyConfig

        let oldVersionProvider = MockAppVersionProvider(appVersion: "1.35.0")
        XCTAssertFalse(config.isEnabled(featureKey: .autofill, versionProvider: oldVersionProvider))
        XCTAssertFalse(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, versionProvider: oldVersionProvider, randomizer: Double.random(in:)))

        let currentVersionProvider = MockAppVersionProvider(appVersion: "1.36.0")
        XCTAssertTrue(config.isEnabled(featureKey: .autofill, versionProvider: currentVersionProvider))
        XCTAssertTrue(config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, versionProvider: currentVersionProvider, randomizer: Double.random(in:)))
    }
    
    let exampleSubfeatureWithRolloutsConfig =
    """
    {
        "features": {
            "autofill": {
                "state": "enabled",
                "exceptions": [],
                "features": {
                    "credentialsSaving": {
                        "state": "enabled",
                        "rollout": {
                            "steps": [{
                                "percent": 5.0
                            }]
                        }
                    }
                },
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!
    
    func clearRolloutData(feature: String, subFeature: String) {
        UserDefaults().set(nil, forKey: "config.\(feature).\(subFeature).enabled")
        UserDefaults().set(nil, forKey: "config.\(feature).\(subFeature).lastRolloutCount")
    }
    
    var mockRandomValue: Double = 0.0
    func mockRandom(in range: Range<Double>) -> Double {
        return mockRandomValue
    }
    
    func testWhenCheckingSubfeatureState_SubfeatureIsEnabledWithSingleRolloutProbability() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleSubfeatureWithRolloutsConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let config = manager.privacyConfig
        
        mockRandomValue = 7.0
        clearRolloutData(feature: "autofill", subFeature: "credentialsSaving")
        var enabled = config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, randomizer: mockRandom(in:))
        XCTAssertFalse(enabled, "Feature should not be enabled if selected value above rollout")
        
        mockRandomValue = 2.0
        clearRolloutData(feature: "autofill", subFeature: "credentialsSaving")
        enabled = config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, randomizer: mockRandom(in:))
        XCTAssertTrue(enabled, "Feature should be enabled if selected value below rollout")
    }
    
    let exampleSubfeatureWithMultipleRolloutsConfig =
    """
    {
        "features": {
            "autofill": {
                "state": "enabled",
                "exceptions": [],
                "features": {
                    "credentialsSaving": {
                        "state": "enabled",
                        "rollout": {
                            "steps": [{
                                "percent": 5.0
                            }, {
                                "percent": 15.0
                            }]
                        }
                    },
                    "credentialsAutofill": {
                        "state": "enabled",
                        "rollout": {
                            "steps": [{
                                "percent": 5.0
                            }, {
                                "percent": 15.0
                            }, {
                                "percent": 25.0
                            }]
                        }
                    },
                    "inlineIconCredentials": {
                        "state": "enabled",
                        "rollout": {
                            "steps": []
                        }
                    },
                    "accessCredentialManagement": {
                        "state": "disabled",
                        "rollout": {
                            "steps": [{
                                "percent": 5.0
                            }, {
                                "percent": 15.0
                            }]
                        }
                    }
                }
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!
    
    func testWhenCheckingSubfeatureState_SubfeatureIsEnabledWithMultipleRolloutProbability() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleSubfeatureWithMultipleRolloutsConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let config = manager.privacyConfig
        
        mockRandomValue = 37
        clearRolloutData(feature: "autofill", subFeature: "credentialsSaving")
        var enabled = config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, randomizer: mockRandom(in:))
        XCTAssertFalse(enabled, "Feature should not be enabled if selected value above rollout")
        
        mockRandomValue = 0.1 // Effective probability of 10.5% in test config
        clearRolloutData(feature: "autofill", subFeature: "credentialsSaving")
        enabled = config.isSubfeatureEnabled(AutofillSubfeature.credentialsSaving, randomizer: mockRandom(in:))
        XCTAssertTrue(enabled, "Feature should not be enabled if selected value above rollout")
        
        mockRandomValue = 37
        clearRolloutData(feature: "autofill", subFeature: "credentialsAutofill")
        enabled = config.isSubfeatureEnabled(AutofillSubfeature.credentialsAutofill, randomizer: mockRandom(in:))
        XCTAssertFalse(enabled, "Feature should not be enabled if selected value above rollout")
        
        mockRandomValue = 0.10 // Effective probability of 11.7% in test config
        clearRolloutData(feature: "autofill", subFeature: "credentialsAutofill")
        enabled = config.isSubfeatureEnabled(AutofillSubfeature.credentialsAutofill, randomizer: mockRandom(in:))
        XCTAssertTrue(enabled, "Feature should not be enabled if selected value above rollout")
    }
    
    func testWhenCheckingSubfeatureStateAndRolloutSizeChanges_SubfeatureIsEnabledWithMultipleRolloutProbability() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleSubfeatureWithMultipleRolloutsConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())

        let config = manager.privacyConfig
        
        clearRolloutData(feature: "autofill", subFeature: "credentialsAutofill")
        mockRandomValue = 0.10
        // Mock that the user has previously seen the rollout and was not chosen
        UserDefaults().set(2, forKey: "config.autofill.credentialsAutofill.lastRolloutCount")
        var enabled = config.isSubfeatureEnabled(AutofillSubfeature.credentialsAutofill, randomizer: mockRandom(in:))

        XCTAssert(enabled, "Subfeature should be enabled when rollout count changes")
        
        clearRolloutData(feature: "autofill", subFeature: "credentialsAutofill")
        // Mock that the user has previously seen the rollout and was not chosen
        UserDefaults().set(3, forKey: "config.autofill.credentialsAutofill.lastRolloutCount")
        enabled = config.isSubfeatureEnabled(AutofillSubfeature.credentialsAutofill, randomizer: mockRandom(in:))

        XCTAssertFalse(enabled, "Subfeature should not be enabled when rollout count does not changes")
    }
    
    func testWhenCheckingSubfeatureStateAndUserIsInARollout_SubfeatureIsEnabled() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleSubfeatureWithMultipleRolloutsConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())
        
        let config = manager.privacyConfig
        
        clearRolloutData(feature: "autofill", subFeature: "credentialsAutofill")
        UserDefaults().set(true, forKey: "config.autofill.credentialsAutofill.enabled")
        XCTAssert(config.isSubfeatureEnabled(AutofillSubfeature.credentialsAutofill), "Subfeature should be enabled if the user has already been selected in a rollout")
    }
    
    func testWhenCheckingSubfeatureStateAndRolloutsIsEmpty_SubfeatrueIsEnabled() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleSubfeatureWithMultipleRolloutsConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())
        
        let config = manager.privacyConfig
        
        clearRolloutData(feature: "autofill", subFeature: "inlineIconCredentials")
        XCTAssert(config.isSubfeatureEnabled(AutofillSubfeature.inlineIconCredentials), "Subfeature should be enabled if rollouts array is empty")
    }
    
    func testWhenCheckingSubfeatureStateWithRolloutsAndSubfeatureDisabled_SubfeatureShouldBeDisabled() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleSubfeatureWithMultipleRolloutsConfig, etag: "test")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider())
        
        let config = manager.privacyConfig
        
        clearRolloutData(feature: "autofill", subFeature: "accessCredentialManagement")
        XCTAssertFalse(config.isSubfeatureEnabled(AutofillSubfeature.accessCredentialManagement), "Subfeature should be enabled if rollouts array is empty")
    }

    func exampleTrackerAllowlistConfig(with state: String) -> Data {
        return
            """
            {
                "features": {
                    "trackerAllowlist": {
                        "state": "\(state)",
                        "settings": {
                            "allowlistedTrackers": {
                                "3lift.com": {
                                    "rules": [
                                        {
                                            "rule": "tlx.3lift.com/header/auction",
                                            "domains": [
                                                "aternos.org"
                                            ],
                                            "reason": "https://github.com/duckduckgo/privacy-configuration/issues/328"
                                        }
                                    ]
                                }
                            }
                        }
                    }
                },
                "unprotectedTemporary": []
            }
            """.data(using: .utf8)!
    }

    func testTrackerAllowlistIsNotEmptyWhenEnabled() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleTrackerAllowlistConfig(with: PrivacyConfigurationData.State.enabled), etag: "test")
        let mockInternalUserStore = MockInternalUserStoring()

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider(store: mockInternalUserStore))
        let config = manager.privacyConfig

        XCTAssertFalse(config.trackerAllowlist.entries.isEmpty)
    }

    func testTrackerAllowlistIsEmptyWhenDisabled() {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: exampleTrackerAllowlistConfig(with: PrivacyConfigurationData.State.disabled), etag: "test")
        let mockInternalUserStore = MockInternalUserStoring()

        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                  internalUserDecider: DefaultInternalUserDecider(store: mockInternalUserStore))
        let config = manager.privacyConfig

        XCTAssert(config.trackerAllowlist.entries.isEmpty)
    }

}
