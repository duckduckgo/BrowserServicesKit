//
//  StripePurchaseFlowTests.swift
//  DuckDuckGo
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

final class StripePurchaseFlowTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSubscriptionOptionsSuccess() async throws {
        let subscriptionEndpointService = SubscriptionEndpointServiceMock(getSubscriptionResult: nil,
                                                                          getProductsResult: .success(SubscriptionMockFactory.productsItems),
                                                                          getCustomerPortalURLResult: nil,
                                                                          confirmPurchaseResult: nil)
        let authEndpointService = AuthEndpointServiceMock(accessTokenResult: nil,
                                                          validateTokenResult: nil,
                                                          createAccountResult: nil,
                                                          storeLoginResult: nil)
        let stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionEndpointService: subscriptionEndpointService,
                                                           authEndpointService: authEndpointService,
                                                           accountManager: AccountManagerMock())
        switch await stripePurchaseFlow.subscriptionOptions() {
        case .success(let success):
            XCTAssertEqual(success.platform, SubscriptionPlatformName.stripe.rawValue)
            XCTAssertEqual(success.options.count, 1)
            XCTAssertEqual(success.features.count, 7)
            let allNames = success.features.compactMap({ feature in feature.name})
            for name in SubscriptionFeatureName.allCases {
                XCTAssertTrue(allNames.contains(name.rawValue))
            }
        case .failure(let failure):
            XCTFail("Unexpected failure: \(failure)")
            break
        }
    }
}
