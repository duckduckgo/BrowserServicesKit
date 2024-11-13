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

import XCTest
import BrowserServicesKit

final class DefaultFeatureFlaggerTests: XCTestCase {
    var internalUserDeciderStore: MockInternalUserStoring!

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
        XCTAssertFalse(featureFlagger.isFeatureOn(forProvider: FeatureFlagSource.disabled))
    }

    func testWhenInternalOnly_returnsIsInternalUserValue() {
        let featureFlagger = createFeatureFlagger()
        internalUserDeciderStore.isInternalUser = false
        XCTAssertFalse(featureFlagger.isFeatureOn(forProvider: FeatureFlagSource.internalOnly))
        internalUserDeciderStore.isInternalUser = true
        XCTAssertTrue(featureFlagger.isFeatureOn(forProvider: FeatureFlagSource.internalOnly))
    }

    func testWhenRemoteDevelopment_isNOTInternalUser_returnsFalse() {
        internalUserDeciderStore.isInternalUser = false
        let embeddedData = Self.embeddedConfig(autofillState: "enabled")
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        XCTAssertFalse(featureFlagger.isFeatureOn(forProvider: FeatureFlagSource.remoteDevelopment(.feature(.autofill))))
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
                                      for sourceProvider: any FeatureFlagProtocol,
                                      file: StaticString = #file,
                                      line: UInt = #line) {
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        XCTAssertEqual(featureFlagger.isFeatureOn(forProvider: sourceProvider), bool, file: file, line: line)
    }
}

extension FeatureFlagSource: FeatureFlagProtocol {
    public static let allCases: [FeatureFlagSource]  = []
    public var supportsLocalOverriding: Bool { false }
    public var rawValue: String { "rawValue" }
    public var source: FeatureFlagSource { self }
}
