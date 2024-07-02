//
//  StorePurchaseManagerTests.swift
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
import StoreKit
import StoreKitTest

final class StorePurchaseManagerTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() async throws {

        // Option 1: make the `SubscriptionsTestConfig.storekit` to work as explained in https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode and https://developer.apple.com/videos/play/wwdc2020/10659/, then test `DefaultStorePurchaseManager` as it is
        /*
        let manager = DefaultStorePurchaseManager()
        try await manager.syncAppleIDAccount()
        XCTAssert(manager.availableProducts.count == 2)
         */

        // Option 2: create a protocol abstracting `StoreKit` from `DefaultStorePurchaseManager` and create a mock that uses SKTestSession
        /*
        let path = Bundle.module.path(forResource: "TestingConfiguration", ofType: "storekit")!
        let session = try SKTestSession(contentsOf: URL(fileURLWithPath: path, isDirectory: false))
        session.disableDialogs = true
        session.clearTransactions()
         */
    }
}
