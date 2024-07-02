//
//  RemoteMessagingProcessingTests.swift
//  DuckDuckGo
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

import BrowserServicesKit
import EmailTestsUtils
import RemoteMessagingTestsUtils
import XCTest
@testable import RemoteMessaging

struct RemoteMessagingProcessorMock: RemoteMessagingProcessing {
    var endpoint: URL
    var configurationFetcher: RemoteMessagingConfigFetching
    var configMatcherProvider: RemoteMessagingConfigMatcherProviding
    var remoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding

    init(
        endpoint: URL = URL(string: "https://example.com/config.json")!,
        configurationFetcher: RemoteMessagingConfigFetching,
        configMatcherProvider: RemoteMessagingConfigMatcherProviding,
        remoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding = MockRemoteMessagingAvailabilityProvider()
    ) {
        self.endpoint = endpoint
        self.configurationFetcher = configurationFetcher
        self.configMatcherProvider = configMatcherProvider
        self.remoteMessagingAvailabilityProvider = remoteMessagingAvailabilityProvider
    }
}

class RemoteMessagingProcessingTests: XCTestCase {

    func testProcessing() async throws {
        let emailManagerStorage = MockEmailManagerStorage()

        // EmailEnabledMatchingAttribute isSignedIn = true
        emailManagerStorage.mockUsername = "username"
        emailManagerStorage.mockToken = "token"

        let emailManager = EmailManager(storage: emailManagerStorage)
        let matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: AppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    emailManager: emailManager,
                    bookmarksCount: 10,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    dismissedMessageIds: []
                ),
                percentileStore: MockRemoteMessagePercentileStore(),
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: []
        )

        let configurationFetcher = MockRemoteMessagingConfigFetcher()
        let configMatcherProvider = MockRemoteMessagingConfigMatcherProvider { _ in
            matcher
        }
        let store = MockRemoteMessagingStore()
        let processor = RemoteMessagingProcessorMock(configurationFetcher: configurationFetcher, configMatcherProvider: configMatcherProvider)

        try await processor.fetchAndProcess(using: store)
    }

}
