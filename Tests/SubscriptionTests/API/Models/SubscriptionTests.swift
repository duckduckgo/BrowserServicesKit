//
//  SubscriptionTests.swift
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

final class SubscriptionTests: XCTestCase {

    func testEquality() throws {
        let a = DDGSubscription(productId: "1",
                                name: "a",
                                billingPeriod: .monthly,
                                startedAt: Date(timeIntervalSince1970: 1000),
                                expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                platform: .apple,
                                status: .autoRenewable)
        let b = DDGSubscription(productId: "1",
                                name: "a",
                                billingPeriod: .monthly,
                                startedAt: Date(timeIntervalSince1970: 1000),
                                expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                platform: .apple,
                                status: .autoRenewable)
        let c = DDGSubscription(productId: "2",
                                name: "a",
                                billingPeriod: .monthly,
                                startedAt: Date(timeIntervalSince1970: 1000),
                                expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                platform: .apple,
                                status: .autoRenewable)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testIfSubscriptionWithGivenStatusIsActive() throws {
        let autoRenewableSubscription = Subscription.make(withStatus: .autoRenewable)
        XCTAssertTrue(autoRenewableSubscription.isActive)

        let notAutoRenewableSubscription = Subscription.make(withStatus: .notAutoRenewable)
        XCTAssertTrue(notAutoRenewableSubscription.isActive)

        let gracePeriodSubscription = Subscription.make(withStatus: .gracePeriod)
        XCTAssertTrue(gracePeriodSubscription.isActive)

        let inactiveSubscription = Subscription.make(withStatus: .inactive)
        XCTAssertFalse(inactiveSubscription.isActive)

        let expiredSubscription = Subscription.make(withStatus: .expired)
        XCTAssertFalse(expiredSubscription.isActive)

        let unknownSubscription = Subscription.make(withStatus: .unknown)
        XCTAssertTrue(unknownSubscription.isActive)
    }

    func testDecoding() throws {
        let rawSubscription = "{\"productId\":\"ddg-privacy-pro-sandbox-monthly-renews-us\",\"name\":\"Monthly Subscription\",\"billingPeriod\":\"Monthly\",\"startedAt\":1718104783000,\"expiresOrRenewsAt\":1723375183000,\"platform\":\"stripe\",\"status\":\"Auto-Renewable\"}"

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let subscription = try decoder.decode(Subscription.self, from: Data(rawSubscription.utf8))

        XCTAssertEqual(subscription.productId, "ddg-privacy-pro-sandbox-monthly-renews-us")
        XCTAssertEqual(subscription.name, "Monthly Subscription")
        XCTAssertEqual(subscription.startedAt, Date(timeIntervalSince1970: 1718104783))
        XCTAssertEqual(subscription.expiresOrRenewsAt, Date(timeIntervalSince1970: 1723375183))
        XCTAssertEqual(subscription.billingPeriod, .monthly)
        XCTAssertEqual(subscription.status, .autoRenewable)
    }

    func testBillingPeriodDecoding() throws {
        let monthly = try JSONDecoder().decode(Subscription.BillingPeriod.self, from: Data("\"Monthly\"".utf8))
        XCTAssertEqual(monthly, Subscription.BillingPeriod.monthly)

        let yearly = try JSONDecoder().decode(Subscription.BillingPeriod.self, from: Data("\"Yearly\"".utf8))
        XCTAssertEqual(yearly, Subscription.BillingPeriod.yearly)

        let unknown = try JSONDecoder().decode(Subscription.BillingPeriod.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, Subscription.BillingPeriod.unknown)
    }

    func testPlatformDecoding() throws {
        let apple = try JSONDecoder().decode(Subscription.Platform.self, from: Data("\"apple\"".utf8))
        XCTAssertEqual(apple, Subscription.Platform.apple)

        let google = try JSONDecoder().decode(Subscription.Platform.self, from: Data("\"google\"".utf8))
        XCTAssertEqual(google, Subscription.Platform.google)

        let stripe = try JSONDecoder().decode(Subscription.Platform.self, from: Data("\"stripe\"".utf8))
        XCTAssertEqual(stripe, Subscription.Platform.stripe)

        let unknown = try JSONDecoder().decode(Subscription.Platform.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, Subscription.Platform.unknown)
    }

    func testStatusDecoding() throws {
        let autoRenewable = try JSONDecoder().decode(Subscription.Status.self, from: Data("\"Auto-Renewable\"".utf8))
        XCTAssertEqual(autoRenewable, Subscription.Status.autoRenewable)

        let notAutoRenewable = try JSONDecoder().decode(Subscription.Status.self, from: Data("\"Not Auto-Renewable\"".utf8))
        XCTAssertEqual(notAutoRenewable, Subscription.Status.notAutoRenewable)

        let gracePeriod = try JSONDecoder().decode(Subscription.Status.self, from: Data("\"Grace Period\"".utf8))
        XCTAssertEqual(gracePeriod, Subscription.Status.gracePeriod)

        let inactive = try JSONDecoder().decode(Subscription.Status.self, from: Data("\"Inactive\"".utf8))
        XCTAssertEqual(inactive, Subscription.Status.inactive)

        let expired = try JSONDecoder().decode(Subscription.Status.self, from: Data("\"Expired\"".utf8))
        XCTAssertEqual(expired, Subscription.Status.expired)

        let unknown = try JSONDecoder().decode(Subscription.Status.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, Subscription.Status.unknown)
    }
}

extension Subscription {

    static func make(withStatus status: Subscription.Status) -> Subscription {
        Subscription(productId: UUID().uuidString,
                     name: "Subscription test #1",
                     billingPeriod: .monthly,
                     startedAt: Date(),
                     expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(+30)),
                     platform: .apple,
                     status: status)
    }
}
