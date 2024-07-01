//
//  SubscriptionEndpointServiceTests.swift
//
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

final class SubscriptionEndpointServiceTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testGetSubscriptionSuccessNoCache() async throws {
        let token = "someToken"
        let subscription = DDGSubscription(productId: "productID",
                                           name: "name",
                                           billingPeriod: .monthly,
                                           startedAt: Date(timeIntervalSince1970: 1000),
                                           expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                           platform: .apple,
                                           status: .autoRenewable)
        let apiService = APIServiceMock(mockAuthHeaders: ["Authorization": "Bearer " + token],
                                        mockAPICallSuccessResult: subscription)
        let service = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging,
                                                         apiService: apiService)
        switch await service.getSubscription(accessToken: token, cachePolicy: .reloadIgnoringLocalCacheData) {
        case .success(let success):
            XCTAssertEqual(subscription, success)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetSubscriptionSuccessCache() async throws {
        // TODO: Implement
    }

    func testGetSubscriptionFailure() async throws {
        // TODO: Implement
    }
}
