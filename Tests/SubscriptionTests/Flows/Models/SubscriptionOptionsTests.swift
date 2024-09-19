//
//  SubscriptionOptionsTests.swift
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

final class SubscriptionOptionsTests: XCTestCase {

    func testEncoding() throws {
        let subscriptionOptions = SubscriptionOptions(platform: "macos",
                                                      options: [
                                                        SubscriptionOption(id: "1",
                                                                           cost: SubscriptionOptionCost(displayPrice: "9 USD", recurrence: "monthly")),
                                                        SubscriptionOption(id: "2",
                                                                           cost: SubscriptionOptionCost(displayPrice: "99 USD", recurrence: "yearly"))
                                                      ],
                                                      features: [
                                                        SubscriptionFeature(name: "vpn"),
                                                        SubscriptionFeature(name: "personal-information-removal"),
                                                        SubscriptionFeature(name: "identity-theft-restoration")
                                                      ])

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try? jsonEncoder.encode(subscriptionOptions)
        let subscriptionOptionsString = String(data: data!, encoding: .utf8)!

        XCTAssertEqual(subscriptionOptionsString, """
{
  "features" : [
    {
      "name" : "vpn"
    },
    {
      "name" : "personal-information-removal"
    },
    {
      "name" : "identity-theft-restoration"
    }
  ],
  "options" : [
    {
      "cost" : {
        "displayPrice" : "9 USD",
        "recurrence" : "monthly"
      },
      "id" : "1"
    },
    {
      "cost" : {
        "displayPrice" : "99 USD",
        "recurrence" : "yearly"
      },
      "id" : "2"
    }
  ],
  "platform" : "macos"
}
""")
    }

    func testSubscriptionOptionCostEncoding() throws {
        let subscriptionOptionCost = SubscriptionOptionCost(displayPrice: "9 USD", recurrence: "monthly")

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys]
        let data = try? jsonEncoder.encode(subscriptionOptionCost)
        let subscriptionOptionCostString = String(data: data!, encoding: .utf8)!

        XCTAssertEqual(subscriptionOptionCostString, "{\"displayPrice\":\"9 USD\",\"recurrence\":\"monthly\"}")
    }

    func testSubscriptionFeatureEncoding() throws {
        let subscriptionFeature = SubscriptionFeature(name: "identity-theft-restoration")

        let data = try? JSONEncoder().encode(subscriptionFeature)
        let subscriptionFeatureString = String(data: data!, encoding: .utf8)!

        XCTAssertEqual(subscriptionFeatureString, "{\"name\":\"identity-theft-restoration\"}")
    }

    func testEmptySubscriptionOptions() throws {
        let empty = SubscriptionOptions.empty

        let platform: SubscriptionPlatformName
#if os(iOS)
        platform = .ios
#else
        platform = .macos
#endif

        XCTAssertEqual(empty.platform, platform.rawValue)
        XCTAssertTrue(empty.options.isEmpty)
        XCTAssertEqual(empty.features.count, SubscriptionFeatureName.allCases.count)
    }
}
