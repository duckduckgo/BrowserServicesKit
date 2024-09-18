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

    public var apiResponse: Result<APIResponseV2, Error>

    public func fetch(request: Networking.APIRequestV2) async throws -> APIResponseV2 {
        switch apiResponse {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}
