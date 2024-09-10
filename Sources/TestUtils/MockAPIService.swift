//
//  MockAPIService.swift
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
import Networking

public struct MockAPIService: APIService {

    public var decodableResponse: Result<Decodable, Error>
    public var apiResponse: Result<APIService.APIResponse, Error>

    public func fetch<T>(request: Networking.APIRequestV2) async throws -> T where T: Decodable {
        switch decodableResponse {
        case .success(let result):
            // swiftlint:disable:next force_cast
            return result as! T
        case .failure(let error):
            throw error
        }
    }

    public func fetch(request: Networking.APIRequestV2) async throws -> (data: Data?, httpResponse: HTTPURLResponse) {
        switch apiResponse {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}
