//
//  JsonToRemoteConfigModelMapper.swift
//  DuckDuckGo
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

struct JsonToRemoteConfigModelMapper {

    static func mapJson(remoteMessagingConfig: RemoteMessageResponse.JsonRemoteMessagingConfig) -> RemoteConfigModel {
        let remoteMessages = JsonToRemoteMessageModelMapper.maps(jsonRemoteMessages: remoteMessagingConfig.messages)
        os_log("remoteMessages mapped = %s", log: .remoteMessaging, type: .debug, String(describing: remoteMessages))
        let rules = JsonToRemoteMessageModelMapper.maps(jsonRemoteRules: remoteMessagingConfig.rules)
        os_log("rules mapped = %s", log: .remoteMessaging, type: .debug, String(describing: rules))
        return RemoteConfigModel(messages: remoteMessages, rules: rules)
    }

}
