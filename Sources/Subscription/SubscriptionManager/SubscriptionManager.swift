//
//  SubscriptionManager.swift
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
import Common
import Macros

public protocol SubscriptionManaging {
    var configuration: SubscriptionConfiguration { get }
    var accountManager: AccountManaging { get }
    var urlProvider: SubscriptionURLProviding { get }
}

public final class SubscriptionManager: SubscriptionManaging {

    public private(set) var configuration: SubscriptionConfiguration
    public private(set) var accountManager: AccountManaging
    public private(set) var urlProvider: SubscriptionURLProviding

    public init(configuration: SubscriptionConfiguration,
                accountManager: AccountManaging,
                urlProvider: SubscriptionURLProviding? = nil) {
        self.configuration = configuration
        self.accountManager = accountManager
        self.urlProvider = urlProvider ?? SubscriptionURLProvider(configuration: configuration)
    }

}
