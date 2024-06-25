//
//  RemoteMessageRequest.swift
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
import Networking

public struct RemoteMessageRequest {

    public let endpoint: URL

    public init(endpoint: URL) {
        self.endpoint = endpoint
    }

    public func getRemoteMessage() async throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        let configuration = APIRequest.Configuration(url: endpoint)
        let request = APIRequest(configuration: configuration, urlSession: .session())

        guard let responseData = try? await request.fetch().data else {
            throw RemoteMessageResponse.StatusError.noData
        }

        do {
            return try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: responseData)
        } catch {
            throw RemoteMessageResponse.StatusError.parsingFailed
        }
    }
}
