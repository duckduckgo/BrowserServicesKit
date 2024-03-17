//
//  SubscriptionFlowProvider.swift
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

public protocol SubscriptionFlowProviding {
    var stripePurchaseFlow: StripePurchaseFlow { get }

    @available(macOS 12.0, iOS 15.0, *)
    var appStorePurchaseFlow: AppStorePurchaseFlow { get }
    @available(macOS 12.0, iOS 15.0, *)
    var appStoreRestoreFlow: AppStoreRestoreFlow { get }
    @available(macOS 12.0, iOS 15.0, *)
    var appStoreAccountManagementFlow: AppStoreAccountManagementFlow { get }
}

public final class SubscriptionFlowProvider: SubscriptionFlowProviding {

    private let accountManager: AccountManaging
    private let serviceProvider: SubscriptionServiceProvider

    init(accountManager: AccountManaging, serviceProvider: SubscriptionServiceProvider) {
        self.accountManager = accountManager
        self.serviceProvider = serviceProvider
    }

    public lazy var stripePurchaseFlow: StripePurchaseFlow = {
        StripePurchaseFlow(accountManager: accountManager,
                           authService: serviceProvider.makeAuthService(),
                           subscriptionService: serviceProvider.makeSubscriptionService())
    }()

    private var _appStorePurchaseFlow: Any?
    @available(macOS 12.0, iOS 15.0, *)
    public var appStorePurchaseFlow: AppStorePurchaseFlow {
        if _appStorePurchaseFlow == nil {
            _appStorePurchaseFlow = AppStorePurchaseFlow(accountManager: accountManager,
                                                         authService: serviceProvider.makeAuthService(),
                                                         subscriptionService: serviceProvider.makeSubscriptionService())
        }
        // swiftlint:disable:next force_cast
        return _appStorePurchaseFlow as! AppStorePurchaseFlow
    }

    private var _appStoreRestoreFlow: Any?
    @available(macOS 12.0, iOS 15.0, *)
    public var appStoreRestoreFlow: AppStoreRestoreFlow {
        if _appStoreRestoreFlow == nil {
            _appStoreRestoreFlow = AppStoreRestoreFlow(accountManager: accountManager,
                                                       authService: serviceProvider.makeAuthService(),
                                                       subscriptionService: serviceProvider.makeSubscriptionService())
        }
        // swiftlint:disable:next force_cast
        return _appStoreRestoreFlow as! AppStoreRestoreFlow
    }

    private var _appStoreAccountManagementFlow: Any?
    @available(macOS 12.0, iOS 15.0, *)
    public var appStoreAccountManagementFlow: AppStoreAccountManagementFlow {
        if _appStoreAccountManagementFlow == nil {
            _appStoreAccountManagementFlow = AppStoreAccountManagementFlow(accountManager: accountManager,
                                                                           authService: serviceProvider.makeAuthService())
        }
        // swiftlint:disable:next force_cast
        return _appStoreAccountManagementFlow as! AppStoreAccountManagementFlow
    }
}
