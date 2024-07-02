//
//  AppStorePurchaseFlowTests.swift
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

import XCTest
@testable import Subscription
import SubscriptionTestingUtilities

final class AppStorePurchaseFlowTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testPurchaseSubscriptionSuccess() async throws {
        let subscriptionEndpointService = SubscriptionMockFactory.subscriptionEndpointService
        let storePurchaseManager = SubscriptionMockFactory.storePurchaseManager
        let appStoreRestoreFlow = SubscriptionMockFactory.appStoreRestoreFlow
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        let authEndpointService = SubscriptionMockFactory.authEndpointService
        let accountManager = SubscriptionMockFactory.accountManager

        let flow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionEndpointService,
                                               storePurchaseManager: storePurchaseManager,
                                               accountManager: accountManager,
                                               appStoreRestoreFlow: appStoreRestoreFlow,
                                               authEndpointService: authEndpointService)

        switch await flow.purchaseSubscription(with: SubscriptionMockFactory.subscription.productId,
                                               emailAccessToken: SubscriptionMockFactory.authToken) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Unexpected failure: \(error.localizedDescription)")
        }
    }
}
