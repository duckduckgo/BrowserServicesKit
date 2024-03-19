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
    var tokenStorage: SubscriptionTokenStorage { get }
    var accountManager: AccountManaging { get }
    var urlProvider: SubscriptionURLProviding { get }
    var serviceProvider: SubscriptionServiceProviding { get }
    var flowProvider: SubscriptionFlowProviding { get }

    var isUserAuthenticated: Bool { get }
    func signOut()
}

public final class SubscriptionManager: SubscriptionManaging {

    public private(set) var configuration: SubscriptionConfiguration
    public private(set) var accountManager: AccountManaging
    public private(set) var tokenStorage: SubscriptionTokenStorage
    public private(set) var urlProvider: SubscriptionURLProviding
    public private(set) var serviceProvider: SubscriptionServiceProviding
    public private(set) var flowProvider: SubscriptionFlowProviding

    public convenience init(configuration: SubscriptionConfiguration) {
        let urlProvider = SubscriptionURLProvider(configuration: configuration)
        let serviceProvider = SubscriptionServiceProvider(configuration: configuration)

        let accountManager = AccountManager(subscriptionAppGroup: configuration.subscriptionAppGroup,
                                            authService: serviceProvider.makeAuthService(),
                                            subscriptionService: serviceProvider.makeSubscriptionService())

        let tokenStorage = SubscriptionTokenKeychainStorage(keychainType: .dataProtection(.named(configuration.subscriptionAppGroup)))

        let flowProvider = SubscriptionFlowProvider(tokenStorage: tokenStorage,
                                                    accountManager: accountManager,
                                                    serviceProvider: serviceProvider)

        self.init(configuration: configuration,
                  accountManager: accountManager,
                  tokenStorage: tokenStorage,
                  urlProvider: urlProvider,
                  serviceProvider: serviceProvider,
                  flowProvider: flowProvider)

        tokenStorage.delegate = self
    }

    public init(configuration: SubscriptionConfiguration,
                accountManager: AccountManaging,
                tokenStorage: SubscriptionTokenStorage,
                urlProvider: SubscriptionURLProviding,
                serviceProvider: SubscriptionServiceProvider,
                flowProvider: SubscriptionFlowProviding) {
        self.configuration = configuration
        self.accountManager = accountManager
        self.tokenStorage = tokenStorage
        self.urlProvider = urlProvider
        self.serviceProvider = serviceProvider
        self.flowProvider = flowProvider
    }

    public var isUserAuthenticated: Bool { tokenStorage.accessToken != nil }

    public func signOut() {
        tokenStorage.clear()
        NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
    }
}

extension SubscriptionManager: GenericKeychainStorageErrorDelegate {
    public func keychainAccessFailed(error: GenericKeychainStorageAccessError) {
        os_log(.error, log: .subscription, "[GenericKeychainStorageErrorDelegate] \(error.errorDescription)")
        assertionFailure("🔥 Something went wrong with GenericKeychainStorage! 🔥")
    }
}
