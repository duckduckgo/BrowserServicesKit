//
//  RemoteMessagingStoring.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public protocol RemoteMessagingStoring {

    func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult)
    func fetchRemoteMessagingConfig() -> RemoteMessagingConfig?
    func fetchScheduledRemoteMessage() -> RemoteMessageModel?
    func fetchRemoteMessage(withId id: String) -> RemoteMessageModel?
    func hasShownRemoteMessage(withId id: String) -> Bool
    func hasDismissedRemoteMessage(withId id: String) -> Bool
    func dismissRemoteMessage(withId id: String)
    func fetchDismissedRemoteMessageIds() -> [String]
    func updateRemoteMessage(withId id: String, asShown shown: Bool)

}
