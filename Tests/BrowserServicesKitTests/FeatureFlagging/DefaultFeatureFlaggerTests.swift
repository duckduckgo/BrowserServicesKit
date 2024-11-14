//
//  DefaultFeatureFlaggerTests.swift
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

import BrowserServicesKit
import TestUtils
import XCTest

final class CapturingFeatureFlagOverriding: FeatureFlagLocalOverriding {

    var overrideCalls: [any FeatureFlagDescribing] = []
    var toggleOverideCalls: [any FeatureFlagDescribing] = []
    var clearOverrideCalls: [any FeatureFlagDescribing] = []
    var clearAllOverrideCallCount: Int = 0

    var override: (any FeatureFlagDescribing) -> Bool? = { _ in nil }

    var actionHandler: any FeatureFlagLocalOverridesHandling = CapturingFeatureFlagLocalOverridesHandler()
    weak var featureFlagger: FeatureFlagger?

    func override<Flag: FeatureFlagDescribing>(for featureFlag: Flag) -> Bool? {
        overrideCalls.append(featureFlag)
        return override(featureFlag)
    }

    func toggleOverride<Flag: FeatureFlagDescribing>(for featureFlag: Flag) {
        toggleOverideCalls.append(featureFlag)
    }

    func clearOverride<Flag: FeatureFlagDescribing>(for featureFlag: Flag) {
        clearOverrideCalls.append(featureFlag)
    }

    func clearAllOverrides<Flag: FeatureFlagDescribing>(for flagType: Flag.Type) {
        clearAllOverrideCallCount += 1
    }
}

final class DefaultFeatureFlaggerTests: XCTestCase {
    var internalUserDeciderStore: MockInternalUserStoring!
    var overrides: CapturingFeatureFlagOverriding!

    override func setUp() {
        super.setUp()
        internalUserDeciderStore = MockInternalUserStoring()
    }

    override func tearDown() {
        internalUserDeciderStore = nil
        super.tearDown()
    }

    func testWhenDisabled_sourceDisabled_returnsFalse() {
        let featureFlagger = createFeatureFlagger()
        XCTAssertFalse(featureFlagger.isFeatureOn(for: FeatureFlagSource.disabled))
    }

    func testWhenInternalOnly_returnsIsInternalUserValue() {
        let featureFlagger = createFeatureFlagger()
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(featureFlagger.isFeatureOn(for: FeatureFlagSource.internalOnly))
        internalUserDeciderStore.isInternalUser = true
        XCTAssertTrue(featureFlagger.isFeatureOn(for: FeatureFlagSource.internalOnly))
    }

    func testWhenRemoteDevelopment_isNOTInternalUser_returnsFalse() {
        internalUserDeciderStore.isInternalUser = false
        let embeddedData = Self.embeddedConfig(autofillState: "enabled")
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        XCTAssertFalse(featureFlagger.isFeatureOn(for: FeatureFlagSource.remoteDevelopment(.feature(.autofill))))
    }

    func testWhenRemoteDevelopment_isInternalUser_whenFeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = true
        let sourceProvider = FeatureFlagSource.remoteDevelopment(.feature(.autofill))

        var embeddedData = Self.embeddedConfig(autofillState: "enabled")
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillState: "disabled")
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    func testWhenRemoteDevelopment_isInternalUser_whenSubfeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        let sourceProvider = FeatureFlagSource.remoteDevelopment(.subfeature(subfeature))

        var embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "disabled"))
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    func testWhenRemoteReleasable_isNOTInternalUser_whenFeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = false
        let sourceProvider = FeatureFlagSource.remoteReleasable(.feature(.autofill))

        var embeddedData = Self.embeddedConfig(autofillState: "enabled")
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillState: "disabled")
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    func testWhenRemoteReleasable_isInternalUser_whenFeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = true
        let sourceProvider = FeatureFlagSource.remoteReleasable(.feature(.autofill))

        var embeddedData = Self.embeddedConfig(autofillState: "enabled")
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillState: "disabled")
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    func testWhenRemoteReleasable_isInternalUser_whenSubfeature_returnsPrivacyConfigValue() {
        internalUserDeciderStore.isInternalUser = true
        let subfeature = AutofillSubfeature.credentialsAutofill
        let sourceProvider = FeatureFlagSource.remoteReleasable(.subfeature(subfeature))

        var embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "enabled"))
        assertFeatureFlagger(with: embeddedData, willReturn: true, for: sourceProvider)

        embeddedData = Self.embeddedConfig(autofillSubfeatureForState: (subfeature: subfeature, state: "disabled"))
        assertFeatureFlagger(with: embeddedData, willReturn: false, for: sourceProvider)
    }

    // MARK: - Overrides

    func testWhenFeatureFlaggerIsInitializedWithLocalOverridesAndUserIsNotInternalThenAllFlagsAreCleared() throws {
        internalUserDeciderStore.isInternalUser = false
        _ = createFeatureFlaggerWithLocalOverrides()
        XCTAssertEqual(overrides.clearAllOverrideCallCount, 1)
    }

    func testWhenLocalOverridesIsSetUpAndUserIsInternalThenLocalOverrideTakesPrecedenceWhenCheckingFlagValue() throws {
        let featureFlagger = createFeatureFlaggerWithLocalOverrides()
        internalUserDeciderStore.isInternalUser = true

        overrides.override = { _ in return true }

        XCTAssertTrue(featureFlagger.isFeatureOn(for: TestFeatureFlag.overridableFlagDisabledByDefault))
        XCTAssertEqual(overrides.overrideCalls.count, 1)
        XCTAssertEqual(try XCTUnwrap(overrides.overrideCalls.first as? TestFeatureFlag), .overridableFlagDisabledByDefault)
    }

    func testWhenLocalOverridesIsSetUpAndUserIsInternalAndAllowOverrideIsFalseThenLocalOverrideIsNotCheckedWhenCheckingFlagValue() throws {
        let featureFlagger = createFeatureFlaggerWithLocalOverrides()
        internalUserDeciderStore.isInternalUser = true

        XCTAssertFalse(featureFlagger.isFeatureOn(for: TestFeatureFlag.overridableFlagDisabledByDefault, allowOverride: false))
        XCTAssertTrue(overrides.overrideCalls.isEmpty)
    }

    func testWhenLocalOverridesIsSetUpAndUserIsNotInternalThenLocalOverrideIsNotCheckedWhenCheckingFlagValue() throws {
        let featureFlagger = createFeatureFlaggerWithLocalOverrides()
        internalUserDeciderStore.isInternalUser = false

        XCTAssertFalse(featureFlagger.isFeatureOn(for: TestFeatureFlag.overridableFlagDisabledByDefault))
        XCTAssertTrue(overrides.overrideCalls.isEmpty)
    }

    // MARK: - Helpers

    private func createFeatureFlagger(withMockedConfigData data: Data = DefaultFeatureFlaggerTests.embeddedConfig()) -> DefaultFeatureFlagger {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: data, etag: "embeddedConfigETag")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                 internalUserDecider: DefaultInternalUserDecider())
        let internalUserDecider = DefaultInternalUserDecider(store: internalUserDeciderStore)
        return DefaultFeatureFlagger(internalUserDecider: internalUserDecider, privacyConfigManager: manager)
    }

    private func createFeatureFlaggerWithLocalOverrides(withMockedConfigData data: Data = DefaultFeatureFlaggerTests.embeddedConfig()) -> DefaultFeatureFlagger {
        let mockEmbeddedData = MockEmbeddedDataProvider(data: data, etag: "embeddedConfigETag")
        let manager = PrivacyConfigurationManager(fetchedETag: nil,
                                                  fetchedData: nil,
                                                  embeddedDataProvider: mockEmbeddedData,
                                                  localProtection: MockDomainsProtectionStore(),
                                                 internalUserDecider: DefaultInternalUserDecider())
        let internalUserDecider = DefaultInternalUserDecider(store: internalUserDeciderStore)

        overrides = CapturingFeatureFlagOverriding()
        return DefaultFeatureFlagger(
            internalUserDecider: internalUserDecider,
            privacyConfigManager: manager,
            localOverrides: overrides,
            for: TestFeatureFlag.self
        )
    }

    private static func embeddedConfig(autofillState: String = "enabled",
                                       autofillSubfeatureForState: (subfeature: AutofillSubfeature, state: String) = (.credentialsAutofill, "enabled")) -> Data {
        """
        {
            "features": {
                "autofill": {
                    "state": "\(autofillState)",
                    "features": {
                        "\(autofillSubfeatureForState.subfeature)": {
                            "state": "\(autofillSubfeatureForState.state)"
                        }
                    },
                    "exceptions": []
                }
            },
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!
    }

    private func assertFeatureFlagger(with embeddedData: Data,
                                      willReturn bool: Bool,
                                      for sourceProvider: any FeatureFlagDescribing,
                                      file: StaticString = #file,
                                      line: UInt = #line) {
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        XCTAssertEqual(featureFlagger.isFeatureOn(for: sourceProvider), bool, file: file, line: line)
    }
}

extension FeatureFlagSource: FeatureFlagDescribing {
    public static let allCases: [FeatureFlagSource]  = []
    public var supportsLocalOverriding: Bool { false }
    public var rawValue: String { "rawValue" }
    public var source: FeatureFlagSource { self }
}
