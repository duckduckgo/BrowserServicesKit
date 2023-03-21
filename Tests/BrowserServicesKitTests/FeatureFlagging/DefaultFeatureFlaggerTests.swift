//
//  FeatureFlaggerTests.swift
//  
//
//  Created by Graeme Arthur on 21/03/2023.
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
                                                  localProtection: MockDomainsProtectionStore())
        let internalUserDecider = DefaultInternalUserDecider(store: internalUserDeciderStore)
        return DefaultFeatureFlagger(internalUserDecider: internalUserDecider, privacyConfig: manager.privacyConfig)
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
                                      for sourceProvider: FeatureFlagSourceProviding,
                                      file: StaticString = #file,
                                      line: UInt = #line) {
        let featureFlagger = createFeatureFlagger(withMockedConfigData: embeddedData)
        XCTAssertEqual(featureFlagger.isFeatureOn(forProvider: sourceProvider), bool, file: file, line: line)
    }
}

extension FeatureFlagSource: FeatureFlagSourceProviding {
    public var source: FeatureFlagSource { self }
}
