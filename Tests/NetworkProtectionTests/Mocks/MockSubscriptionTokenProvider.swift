//
//  MockSubscriptionTokenProvider.swift
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
import Subscription

public class MockSubscriptionTokenProvider: SubscriptionTokenProvider {

    public var tokenResult: Result<String, Error>?

    public func getAccessToken() async throws -> String {
        guard let tokenResult else {
            throw SubscriptionManagerError.tokenUnavailable(error: nil)
        }
        switch tokenResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
    
    public func removeAccessToken() {
        tokenResult = nil
    }
}
