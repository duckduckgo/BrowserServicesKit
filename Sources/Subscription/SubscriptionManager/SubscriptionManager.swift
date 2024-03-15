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

public protocol SubscriptionManaging {
    var configuration: SubscriptionConfiguration { get }
    var accountManager: AccountManaging { get }
    var urlProvider: SubscriptionURLProviding { get }
    var serviceProvider: SubscriptionServiceProvider { get }
    var flowProvider: SubscriptionFlowProviding { get }
}

public final class SubscriptionManager: SubscriptionManaging {

    public private(set) var configuration: SubscriptionConfiguration
    public private(set) var accountManager: AccountManaging
    public private(set) var urlProvider: SubscriptionURLProviding
    public private(set) var serviceProvider: SubscriptionServiceProvider
    public private(set) var flowProvider: SubscriptionFlowProviding

    public convenience init(configuration: SubscriptionConfiguration,
                            accountManager: AccountManaging) {
        let urlProvider = SubscriptionURLProvider(configuration: configuration)
        let serviceProvider = SubscriptionServiceProvider(configuration: configuration)
        let flowProvider = SubscriptionFlowProvider(accountManager: accountManager,
                                                    serviceProvider: serviceProvider)
        self.init(configuration: configuration,
                  accountManager: accountManager,
                  urlProvider: urlProvider,
                  serviceProvider: serviceProvider,
                  flowProvider: flowProvider)
    }

    public init(configuration: SubscriptionConfiguration,
                accountManager: AccountManaging,
                urlProvider: SubscriptionURLProviding,
                serviceProvider: SubscriptionServiceProvider,
                flowProvider: SubscriptionFlowProviding) {
        self.configuration = configuration
        self.accountManager = accountManager
        self.urlProvider = urlProvider
        self.serviceProvider = serviceProvider
        self.flowProvider = flowProvider
    }

}
