//
//  SubscriptionFeatureAvailabilityTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common
import Combine
@testable import Subscription
@testable import BrowserServicesKit

final class SubscriptionFeatureAvailabilityTests: XCTestCase {

    var internalUserDeciderStore: MockInternalUserStoring!
    var privacyConfig: MockPrivacyConfiguration!
    var privacyConfigurationManager: MockPrivacyConfigurationManager!

    override func setUp() {
        super.setUp()
        internalUserDeciderStore = MockInternalUserStoring()
        privacyConfig = MockPrivacyConfiguration()

        privacyConfigurationManager = MockPrivacyConfigurationManager(privacyConfig: privacyConfig,
                                                                      internalUserDecider: DefaultInternalUserDecider(store: internalUserDeciderStore))
    }

    override func tearDown() {
        internalUserDeciderStore = nil
        privacyConfig = nil

        privacyConfigurationManager = nil
        super.tearDown()
    }

    // MARK: - Tests for App Store

    let environmentStore = SubscriptionEnvironment(serviceEnvironment: .production, platform: .appStore)
    let environmentStripe = SubscriptionEnvironment(serviceEnvironment: .production, platform: .stripe)

    func testSubscriptionFeatureNotAvailableWhenAllFlagsDisabledAndNotInternalUser() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunched))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverride))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStore)
        XCTAssertFalse(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertFalse(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testSubscriptionFeatureAvailableWhenIsLaunchedFlagEnabled() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.isLaunched, .allowPurchase])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunched))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverride))
        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStore)
        XCTAssertTrue(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testSubscriptionFeatureAvailableWhenIsLaunchedOverrideFlagEnabled() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.isLaunchedOverride, .allowPurchase])

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunched))
        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverride))
        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStore)
        XCTAssertTrue(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testSubscriptionFeatureAvailableAndPurchaseNotAllowed() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.isLaunched])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunched))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverride))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStore)
        XCTAssertTrue(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertFalse(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testSubscriptionFeatureAvailableWhenAllFlagsDisabledAndInternalUser() {
        internalUserDeciderStore.isInternalUser = true
        XCTAssertTrue(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunched))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverride))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStore)
        XCTAssertTrue(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    // MARK: - Tests for Stripe

    func testStripeSubscriptionFeatureNotAvailableWhenAllFlagsDisabledAndNotInternalUser() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedStripe))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverrideStripe))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStripe)
        XCTAssertFalse(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertFalse(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testStripeSubscriptionFeatureAvailableWhenIsLaunchedFlagEnabled() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.isLaunchedStripe, .allowPurchaseStripe])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedStripe))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverrideStripe))
        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStripe)
        XCTAssertTrue(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testStripeSubscriptionFeatureAvailableWhenIsLaunchedOverrideFlagEnabled() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.isLaunchedOverrideStripe, .allowPurchaseStripe])

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedStripe))
        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverrideStripe))
        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStripe)
        XCTAssertTrue(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testStripeSubscriptionFeatureAvailableAndPurchaseNotAllowed() {
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(internalUserDeciderStore.isInternalUser)

        privacyConfig.isSubfeatureEnabledCheck = makeSubfeatureEnabledCheck(for: [.isLaunchedStripe])

        XCTAssertTrue(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedStripe))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverrideStripe))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStripe)
        XCTAssertTrue(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertFalse(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    func testStripeSubscriptionFeatureAvailableWhenAllFlagsDisabledAndInternalUser() {
        internalUserDeciderStore.isInternalUser = true
        XCTAssertTrue(internalUserDeciderStore.isInternalUser)

        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedStripe))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.isLaunchedOverrideStripe))
        XCTAssertFalse(privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe))

        let subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                     subscriptionEnvironment: environmentStripe)
        XCTAssertTrue(subscriptionFeatureAvailability.isFeatureAvailable)
        XCTAssertTrue(subscriptionFeatureAvailability.isSubscriptionPurchaseAllowed)
    }

    // MARK: - Helper

    private func makeSubfeatureEnabledCheck(for enabledSubfeatures: [PrivacyProSubfeature]) -> (any PrivacySubfeature) -> Bool {
        return {
            guard let subfeature = $0 as? PrivacyProSubfeature else { return false }
            return enabledSubfeatures.contains(subfeature)
        }
    }
}

class MockPrivacyConfiguration: PrivacyConfiguration {

    func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> Bool { true }

    func stateFor(featureKey: BrowserServicesKit.PrivacyFeature, versionProvider: BrowserServicesKit.AppVersionProvider) -> BrowserServicesKit.PrivacyConfigurationFeatureState {
        return .enabled
    }

    var isSubfeatureEnabledCheck: ((any PrivacySubfeature) -> Bool)?

    func isSubfeatureEnabled(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> Bool {
        isSubfeatureEnabledCheck?(subfeature) ?? false
    }

    func stateFor(_ subfeature: any PrivacySubfeature, versionProvider: AppVersionProvider, randomizer: (Range<Double>) -> Double) -> PrivacyConfigurationFeatureState {
        if isSubfeatureEnabledCheck?(subfeature) == true {
            return .enabled
        }
        return .disabled(.disabledInConfig)
    }

    var identifier: String = "abcd"
    var userUnprotectedDomains: [String] = []
    var tempUnprotectedDomains: [String] = []
    var trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist = .init(json: ["state": "disabled"])!
    func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] { [] }
    func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool { true }
    func isProtected(domain: String?) -> Bool { false }
    func isUserUnprotected(domain: String?) -> Bool { false }
    func isTempUnprotected(domain: String?) -> Bool { false }
    func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool { false }
    func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings { .init() }
    func userEnabledProtection(forDomain: String) {}
    func userDisabledProtection(forDomain: String) {}
}

class MockPrivacyConfigurationManager: PrivacyConfigurationManaging {
    var currentConfig: Data = .init()
    var updatesSubject = PassthroughSubject<Void, Never>()
    let updatesPublisher: AnyPublisher<Void, Never>
    var privacyConfig: PrivacyConfiguration
    let internalUserDecider: InternalUserDecider
    var toggleProtectionsCounter = ToggleProtectionsCounter(eventReporting: EventMapping<ToggleProtectionsCounterEvent> { _, _, _, _ in })
    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        .downloaded
    }

    init(privacyConfig: PrivacyConfiguration, internalUserDecider: InternalUserDecider) {
        self.updatesPublisher = updatesSubject.eraseToAnyPublisher()
        self.privacyConfig = privacyConfig
        self.internalUserDecider = internalUserDecider
    }
}
