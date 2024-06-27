//
//  RemoteMessagingProcessing.swift
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

public protocol RemoteMessagingConfigMatcherProviding {
    func refreshConfigMatcher(using store: RemoteMessagingStoring) async -> RemoteMessagingConfigMatcher
}

public protocol RemoteMessagingProcessing: RemoteMessagingFetching {
    var endpoint: URL { get }
    var configMatcherProvider: RemoteMessagingConfigMatcherProviding { get }

    func fetchAndProcess(using store: RemoteMessagingStoring) async throws
}

public extension RemoteMessagingProcessing {

    func fetchAndProcess(using store: RemoteMessagingStoring) async throws {
        do {
            let statusResponse = try await fetchRemoteMessages(request: RemoteMessageRequest(endpoint: endpoint))

            os_log("Successfully fetched remote messages", log: .remoteMessaging, type: .debug)

            let remoteMessagingConfigMatcher = await configMatcherProvider.refreshConfigMatcher(using: store)

            let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
            let config = store.fetchRemoteMessagingConfig()

            if let processorResult = processor.process(jsonRemoteMessagingConfig: statusResponse, currentConfig: config) {
                store.saveProcessedResult(processorResult)
            }

        } catch {
            os_log("Failed to fetch remote messages", log: .remoteMessaging, type: .error)
            throw error
        }
    }
}
