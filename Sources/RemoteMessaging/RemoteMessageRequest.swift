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

    public func getRemoteMessage(completionHandler: @escaping (Result<RemoteMessageResponse.JsonRemoteMessagingConfig, RemoteMessageResponse.StatusError>) -> Void) {
        let configuration = APIRequest.Configuration(url: endpoint)
        let request = APIRequest(configuration: configuration, urlSession: .session())

        request.fetch { response, error in
            guard let data = response?.data, error == nil else {
                completionHandler(.failure(.noData))
                return
            }

            do {
                let decoder  = JSONDecoder()
                let response = try decoder.decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: data)

                completionHandler(.success(response))
            } catch {
                completionHandler(.failure(.parsingFailed))
            }
        }
    }
}
