//
//  RemoteMessagingConfigProcessor.swift
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

import Common
import Foundation

public struct RemoteMessagingConfigProcessor {

    public struct ProcessorResult {
        public let version: Int64
        public let message: RemoteMessageModel?
    }

    let remoteMessagingConfigMatcher: RemoteMessagingConfigMatcher

    public init(remoteMessagingConfigMatcher: RemoteMessagingConfigMatcher) {
        self.remoteMessagingConfigMatcher = remoteMessagingConfigMatcher
    }

    public func process(jsonRemoteMessagingConfig: RemoteMessageResponse.JsonRemoteMessagingConfig,
                        currentConfig: RemoteMessagingConfig?) -> ProcessorResult? {
        os_log("Processing version %s", log: .remoteMessaging, type: .debug, String(jsonRemoteMessagingConfig.version))

        let currentVersion = currentConfig?.version ?? 0
        let newVersion     = jsonRemoteMessagingConfig.version

        let isNewVersion = newVersion != currentVersion

        if isNewVersion || shouldProcessConfig(currentConfig) {
            let config = JsonToRemoteConfigModelMapper.mapJson(
                remoteMessagingConfig: jsonRemoteMessagingConfig,
                surveyActionMapper: remoteMessagingConfigMatcher.surveyActionMapper
            )
            let message = remoteMessagingConfigMatcher.evaluate(remoteConfig: config)
            os_log("Message to present next: %s", log: .remoteMessaging, type: .debug, message.debugDescription)

            return ProcessorResult(version: jsonRemoteMessagingConfig.version, message: message)
        }

        return nil
    }

    func shouldProcessConfig(_ currentConfig: RemoteMessagingConfig?) -> Bool {
        // TODO: Remove  before merging
        return true

        guard let currentConfig = currentConfig else {
            return true
        }

        return currentConfig.invalidate || currentConfig.expired()
    }
}
