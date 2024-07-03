//
//  MockRemoteMessagingStore.swift
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

import Foundation
import RemoteMessaging

public struct MockRemoteMessagingStore: RemoteMessagingStoring {

    public var remoteMessagingConfig: RemoteMessagingConfig?
    public var scheduledRemoteMessage: RemoteMessageModel?
    public var remoteMessages: [String: RemoteMessageModel]
    public var shownRemoteMessagesIDs: [String]
    public var dismissedRemoteMessagesIDs: [String]

    public init(
        remoteMessagingConfig: RemoteMessagingConfig? = nil,
        scheduledRemoteMessage: RemoteMessageModel? = nil,
        remoteMessages: [String : RemoteMessageModel] = [:],
        shownRemoteMessagesIDs: [String] = [],
        dismissedRemoteMessagesIDs: [String] = []
    ) {
        self.remoteMessagingConfig = remoteMessagingConfig
        self.scheduledRemoteMessage = scheduledRemoteMessage
        self.remoteMessages = remoteMessages
        self.shownRemoteMessagesIDs = shownRemoteMessagesIDs
        self.dismissedRemoteMessagesIDs = dismissedRemoteMessagesIDs
    }

    public func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult) {
    }

    public func fetchRemoteMessagingConfig() -> RemoteMessagingConfig? {
        remoteMessagingConfig
    }

    public func fetchScheduledRemoteMessage() -> RemoteMessageModel? {
        scheduledRemoteMessage
    }

    public func fetchRemoteMessage(withId id: String) -> RemoteMessageModel? {
        remoteMessages[id]
    }

    public func hasShownRemoteMessage(withId id: String) -> Bool {
        shownRemoteMessagesIDs.contains(id)
    }

    public func hasDismissedRemoteMessage(withId id: String) -> Bool {
        dismissedRemoteMessagesIDs.contains(id)
    }

    public func dismissRemoteMessage(withId id: String) {}

    public func fetchDismissedRemoteMessageIds() -> [String] {
        dismissedRemoteMessagesIDs
    }

    public func updateRemoteMessage(withId id: String, asShown shown: Bool) {}
}
