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
        let a = PrivacyProSubscription(productId: "1",
                                       name: "a",
                                       billingPeriod: .monthly,
                                       startedAt: Date(timeIntervalSince1970: 1000),
                                       expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                       platform: .apple,
                                       status: .autoRenewable)
        let b = PrivacyProSubscription(productId: "1",
                                       name: "a",
                                       billingPeriod: .monthly,
                                       startedAt: Date(timeIntervalSince1970: 1000),
                                       expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                       platform: .apple,
                                       status: .autoRenewable)
        let c = PrivacyProSubscription(productId: "2",
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
        let autoRenewableSubscription = PrivacyProSubscription.make(withStatus: .autoRenewable)
        XCTAssertTrue(autoRenewableSubscription.isActive)

        let notAutoRenewableSubscription = PrivacyProSubscription.make(withStatus: .notAutoRenewable)
        XCTAssertTrue(notAutoRenewableSubscription.isActive)

        let gracePeriodSubscription = PrivacyProSubscription.make(withStatus: .gracePeriod)
        XCTAssertTrue(gracePeriodSubscription.isActive)

        let inactiveSubscription = PrivacyProSubscription.make(withStatus: .inactive)
        XCTAssertFalse(inactiveSubscription.isActive)

        let expiredSubscription = PrivacyProSubscription.make(withStatus: .expired)
        XCTAssertFalse(expiredSubscription.isActive)

        let unknownSubscription = PrivacyProSubscription.make(withStatus: .unknown)
        XCTAssertTrue(unknownSubscription.isActive)
    }

    func testDecoding() throws {
        let rawSubscription = "{\"productId\":\"ddg-privacy-pro-sandbox-monthly-renews-us\",\"name\":\"Monthly Subscription\",\"billingPeriod\":\"Monthly\",\"startedAt\":1718104783000,\"expiresOrRenewsAt\":1723375183000,\"platform\":\"stripe\",\"status\":\"Auto-Renewable\"}"

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let subscription = try decoder.decode(PrivacyProSubscription.self, from: Data(rawSubscription.utf8))

        XCTAssertEqual(subscription.productId, "ddg-privacy-pro-sandbox-monthly-renews-us")
        XCTAssertEqual(subscription.name, "Monthly Subscription")
        XCTAssertEqual(subscription.startedAt, Date(timeIntervalSince1970: 1718104783))
        XCTAssertEqual(subscription.expiresOrRenewsAt, Date(timeIntervalSince1970: 1723375183))
        XCTAssertEqual(subscription.billingPeriod, .monthly)
        XCTAssertEqual(subscription.status, .autoRenewable)
    }

    func testBillingPeriodDecoding() throws {
        let monthly = try JSONDecoder().decode(PrivacyProSubscription.BillingPeriod.self, from: Data("\"Monthly\"".utf8))
        XCTAssertEqual(monthly, PrivacyProSubscription.BillingPeriod.monthly)

        let yearly = try JSONDecoder().decode(PrivacyProSubscription.BillingPeriod.self, from: Data("\"Yearly\"".utf8))
        XCTAssertEqual(yearly, PrivacyProSubscription.BillingPeriod.yearly)

        let unknown = try JSONDecoder().decode(PrivacyProSubscription.BillingPeriod.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, PrivacyProSubscription.BillingPeriod.unknown)
    }

    func testPlatformDecoding() throws {
        let apple = try JSONDecoder().decode(PrivacyProSubscription.Platform.self, from: Data("\"apple\"".utf8))
        XCTAssertEqual(apple, PrivacyProSubscription.Platform.apple)

        let google = try JSONDecoder().decode(PrivacyProSubscription.Platform.self, from: Data("\"google\"".utf8))
        XCTAssertEqual(google, PrivacyProSubscription.Platform.google)

        let stripe = try JSONDecoder().decode(PrivacyProSubscription.Platform.self, from: Data("\"stripe\"".utf8))
        XCTAssertEqual(stripe, PrivacyProSubscription.Platform.stripe)

        let unknown = try JSONDecoder().decode(PrivacyProSubscription.Platform.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, PrivacyProSubscription.Platform.unknown)
    }

    func testStatusDecoding() throws {
        let autoRenewable = try JSONDecoder().decode(PrivacyProSubscription.Status.self, from: Data("\"Auto-Renewable\"".utf8))
        XCTAssertEqual(autoRenewable, PrivacyProSubscription.Status.autoRenewable)

        let notAutoRenewable = try JSONDecoder().decode(PrivacyProSubscription.Status.self, from: Data("\"Not Auto-Renewable\"".utf8))
        XCTAssertEqual(notAutoRenewable, PrivacyProSubscription.Status.notAutoRenewable)

        let gracePeriod = try JSONDecoder().decode(PrivacyProSubscription.Status.self, from: Data("\"Grace Period\"".utf8))
        XCTAssertEqual(gracePeriod, PrivacyProSubscription.Status.gracePeriod)

        let inactive = try JSONDecoder().decode(PrivacyProSubscription.Status.self, from: Data("\"Inactive\"".utf8))
        XCTAssertEqual(inactive, PrivacyProSubscription.Status.inactive)

        let expired = try JSONDecoder().decode(PrivacyProSubscription.Status.self, from: Data("\"Expired\"".utf8))
        XCTAssertEqual(expired, PrivacyProSubscription.Status.expired)

        let unknown = try JSONDecoder().decode(PrivacyProSubscription.Status.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, PrivacyProSubscription.Status.unknown)
    }
}

extension PrivacyProSubscription {

    static func make(withStatus status: PrivacyProSubscription.Status) -> PrivacyProSubscription {
        PrivacyProSubscription(productId: UUID().uuidString,
                               name: "Subscription test #1",
                               billingPeriod: .monthly,
                               startedAt: Date(),
                               expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(+30)),
                               platform: .apple,
                               status: status)
    }
}
