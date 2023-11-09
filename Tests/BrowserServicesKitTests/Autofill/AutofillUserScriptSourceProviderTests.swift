//
//  AutofillUserScriptSourceProviderTests.swift
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

import XCTest
import BrowserServicesKit

final class AutofillUserScriptSourceProviderTests: XCTestCase {

    let embeddedConfig =
    """
    {
        "features": {
            "autofill": {
                "status": "enabled",
                "exceptions": []
            }
        },
        "unprotectedTemporary": []
    }
    """.data(using: .utf8)!
    lazy var privacyConfig = AutofillTestHelper.preparePrivacyConfig(embeddedConfig: embeddedConfig)
    let properties = ContentScopeProperties(gpcEnabled: false, sessionKey: "1234", featureToggles: ContentScopeFeatureToggles.allTogglesOn)

    func testWhenBuildWithLoadJSThenSourceStrIsBuilt() {
        let autofillSourceProvider = DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfig,
                                                                           properties: properties)
            .withJSLoading()
            .build()
        XCTAssertFalse(autofillSourceProvider.source.isEmpty)
    }

    func testWhenBuildRuntimeConfigurationThenConfigurationIsBuilt() {
        let runtimeConfiguration = DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfig,
                                                                         properties: properties)
            .build()
            .buildRuntimeConfigResponse()

        XCTAssertNotNil(runtimeConfiguration)
        XCTAssertFalse(runtimeConfiguration!.isEmpty)
    }
}
