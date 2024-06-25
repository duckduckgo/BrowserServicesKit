//
//  RemoteMessagingClientBase.swift
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
import Common
import Foundation

public protocol RemoteMessagingDataSource {

    var statisticsStore: StatisticsStore! { get }
    var variantManager: VariantManager! { get }
    var surveyActionMapper: RemoteMessagingSurveyActionMapping! { get }

    var appTheme: String { get }
    var isInternalUser: Bool { get }

    var bookmarksCount: Int { get }
    var favoritesCount: Int { get }

    var daysSinceNetworkProtectionEnabled: Int { get }

    var isWidgetInstalled: Bool { get }
    var isPrivacyProEligibleUser: Bool { get }
    var isPrivacyProSubscriber: Bool { get }
    var privacyProDaysSinceSubscribed: Int { get }
    var privacyProDaysUntilExpiry: Int { get }
    var privacyProPurchasePlatform: String? { get }
    var isPrivacyProSubscriptionActive: Bool { get }
    var isPrivacyProSubscriptionExpiring: Bool { get }
    var isPrivacyProSubscriptionExpired: Bool { get }

    func refreshState() async
}

open class RemoteMessagingClientBase: RemoteMessagingFetching {

    public let endpoint: URL
    public let dataSource: RemoteMessagingDataSource

    public init(endpoint: URL, dataSource: RemoteMessagingDataSource) {
        self.endpoint = endpoint
        self.dataSource = dataSource
    }

    public func fetchAndProcess(remoteMessagingStore: RemoteMessagingStore) async throws {

        do {
            let statusResponse = try await fetchRemoteMessages(request: RemoteMessageRequest(endpoint: endpoint))

            os_log("Successfully fetched remote messages", log: .remoteMessaging, type: .debug)

            await dataSource.refreshState()

            let dismissedMessageIds = remoteMessagingStore.fetchDismissedRemoteMessageIds()

            let remoteMessagingConfigMatcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: AppAttributeMatcher(statisticsStore: dataSource.statisticsStore,
                                                         variantManager: dataSource.variantManager,
                                                         isInternalUser: dataSource.isInternalUser),
                userAttributeMatcher: UserAttributeMatcher(statisticsStore: dataSource.statisticsStore,
                                                           variantManager: dataSource.variantManager,
                                                           bookmarksCount: dataSource.bookmarksCount,
                                                           favoritesCount: dataSource.favoritesCount,
                                                           appTheme: dataSource.appTheme,
                                                           isWidgetInstalled: dataSource.isWidgetInstalled,
                                                           daysSinceNetPEnabled: dataSource.daysSinceNetworkProtectionEnabled,
                                                           isPrivacyProEligibleUser: dataSource.isPrivacyProEligibleUser,
                                                           isPrivacyProSubscriber: dataSource.isPrivacyProSubscriber,
                                                           privacyProDaysSinceSubscribed: dataSource.privacyProDaysSinceSubscribed,
                                                           privacyProDaysUntilExpiry: dataSource.privacyProDaysUntilExpiry,
                                                           privacyProPurchasePlatform: dataSource.privacyProPurchasePlatform,
                                                           isPrivacyProSubscriptionActive: dataSource.isPrivacyProSubscriptionActive,
                                                           isPrivacyProSubscriptionExpiring: dataSource.isPrivacyProSubscriptionExpiring,
                                                           isPrivacyProSubscriptionExpired: dataSource.isPrivacyProSubscriptionExpired,
                                                           dismissedMessageIds: dismissedMessageIds),
                percentileStore: RemoteMessagingPercentileUserDefaultsStore(userDefaults: .standard),
                surveyActionMapper: dataSource.surveyActionMapper,
                dismissedMessageIds: dismissedMessageIds
            )

            let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
            let config = remoteMessagingStore.fetchRemoteMessagingConfig()

            if let processorResult = processor.process(jsonRemoteMessagingConfig: statusResponse,
                                                       currentConfig: config) {
                remoteMessagingStore.saveProcessedResult(processorResult)
            }

        } catch {
            os_log("Failed to fetch remote messages", log: .remoteMessaging, type: .error)
            throw error
        }
    }

}
