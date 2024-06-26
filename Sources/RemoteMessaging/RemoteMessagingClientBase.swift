//
//  RemoteMessagingClientBase.swift
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
    func refreshConfigMatcher(with store: RemoteMessagingStoring) async -> RemoteMessagingConfigMatcher
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

            let remoteMessagingConfigMatcher = await dataSource.refreshConfigMatcher(with: remoteMessagingStore)

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
