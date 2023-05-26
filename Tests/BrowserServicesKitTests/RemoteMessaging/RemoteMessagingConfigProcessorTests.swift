//
//  JsonRemoteMessagingConfigMapperTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
@testable import BrowserServicesKit

class RemoteMessagingConfigProcessorTests: XCTestCase {

    private var data = JsonTestDataLoader()

    func testNonBreakingChangesInNewVersion() throws {

        let json =
"""
    {
  "version": 4,
  "messages": [
    {
      "id": "macos_promo_may2023",
      "content": {
        "messageType": "big_single_action",
        "titleText": "Get DuckDuckGo Browser for Mac",
        "descriptionText": "Search privately and block trackers and annoying cookie pop-ups on your Mac for free!",
        "placeholder": "MacComputer",
        "primaryActionText": "Learn More",
        "primaryAction": {
          "type": "share",
          "value": "https://duckduckgo.com/mac?rmf=mac",
          "nonBreakingChange": "New fields should not be considered breaking"
        }
      },
      "matchingRules": [
        1
      ]
    }
  ],
  "rules": []
}
"""

        _ = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: json.data(using: .utf8)!)

    }

    func testBreakingChangesInNewVersion() throws {

        let json =
"""
    {
  "version": 4,
  "messages": [
    {
      "id": "macos_promo_may2023",
      "content": {
        "messageType": "big_single_action",
        "titleText": "Get DuckDuckGo Browser for Mac",
        "descriptionText": "Search privately and block trackers and annoying cookie pop-ups on your Mac for free!",
        "placeholder": "MacComputer",
        "primaryActionText": "Learn More",
        "primaryAction": {
          "type": "share",
          "value": ["https://duckduckgo.com/mac?rmf=mac", "THIS IS A BREAKING CHANGE"]
        }
      },
      "matchingRules": [
        1
      ]
    }
  ],
  "rules": []
}
"""

        _ = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: json.data(using: .utf8)!)

    }

    func testWhenNewVersionThenShouldHaveBeenProcessedAndResultReturned() throws {
        let jsonRemoteMessagingConfig = try decodeJson(fileName: "Resources/remote-messaging-config.json")
        XCTAssertNotNil(jsonRemoteMessagingConfig)

        let remoteMessagingConfigMatcher = RemoteMessagingConfigMatcher(
            appAttributeMatcher: AppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
            userAttributeMatcher: UserAttributeMatcher(statisticsStore: MockStatisticsStore(),
                                                       variantManager: MockVariantManager(),
                                                       bookmarksCount: 0,
                                                       favoritesCount: 0,
                                                       appTheme: "light",
                                                       isWidgetInstalled: false),
            dismissedMessageIds: []
        )

        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
        let config: RemoteMessagingConfig = RemoteMessagingConfig(version: jsonRemoteMessagingConfig.version - 1,
                                                                  invalidate: false,
                                                                  evaluationTimestamp: Date())

        let processorResult = processor.process(jsonRemoteMessagingConfig: jsonRemoteMessagingConfig, currentConfig: config)
        XCTAssertNotNil(processorResult)
        XCTAssertEqual(processorResult?.version, jsonRemoteMessagingConfig.version)
        XCTAssertNotNil(processorResult?.message)
    }

    func testWhenSameVersionThenNotProcessedAndResultNil() throws {
        let jsonRemoteMessagingConfig = try decodeJson(fileName: "Resources/remote-messaging-config-malformed.json")
        XCTAssertNotNil(jsonRemoteMessagingConfig)

        let remoteMessagingConfigMatcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: AppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: UserAttributeMatcher(statisticsStore: MockStatisticsStore(),
                                                           variantManager: MockVariantManager(),
                                                           bookmarksCount: 0,
                                                           favoritesCount: 0,
                                                           appTheme: "light",
                                                           isWidgetInstalled: false),
                dismissedMessageIds: [])

        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
        let config: RemoteMessagingConfig = RemoteMessagingConfig(version: jsonRemoteMessagingConfig.version,
                                                                  invalidate: false,
                                                                  evaluationTimestamp: Date())

        let result = processor.process(jsonRemoteMessagingConfig: jsonRemoteMessagingConfig, currentConfig: config)
        XCTAssertNil(result)
    }

    func decodeJson(fileName: String) throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        let validJson = data.fromJsonFile(fileName)
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        XCTAssertNotNil(remoteMessagingConfig)

        return remoteMessagingConfig
    }
}
