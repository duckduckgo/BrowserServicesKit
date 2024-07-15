//
//  MockRemoteMessagingConfigFetcher.swift
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
@testable import RemoteMessaging

public class MockRemoteMessagingConfigFetcher: RemoteMessagingConfigFetching {

    public init(config: RemoteMessageResponse.JsonRemoteMessagingConfig = .empty) {
        self.config = config
    }

    public var error: Error?
    public var config: RemoteMessageResponse.JsonRemoteMessagingConfig

    public func fetchRemoteMessagingConfig() async throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        if let error {
            throw error
        }
        return config
    }
}

public extension RemoteMessageResponse.JsonRemoteMessagingConfig {
    static let empty: Self = .init(version: 0, messages: [], rules: [])
}
