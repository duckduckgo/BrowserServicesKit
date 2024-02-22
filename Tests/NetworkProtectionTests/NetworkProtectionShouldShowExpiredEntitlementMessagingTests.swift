//
//  NetworkProtectionShouldShowExpiredEntitlementMessagingTests.swift
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
@testable import NetworkProtection

final class NetworkProtectionShouldShowExpiredEntitlementMessagingTests: XCTestCase {
    var testDefaults: UserDefaults!

    private static let showsAlertAndNotification = UserDefaults.ExpiredEntitlementMessaging(showsAlert: true, showsNotification: true)
    private static let showsAlertOnly = UserDefaults.ExpiredEntitlementMessaging(showsAlert: true, showsNotification: false)
    private static let showsNotificationOnly = UserDefaults.ExpiredEntitlementMessaging(showsAlert: false, showsNotification: true)

    override func setUp() {
        super.setUp()

        testDefaults = UserDefaults(suiteName: "com.duckduckgo.browserserviceskit.tests.\(String(describing: type(of: self)))")!
        testDefaults.shouldShowExpiredEntitlementMessaging = nil
    }

    func testMessagingStateTransition() {
        XCTAssertNil(testDefaults.shouldShowExpiredEntitlementMessaging)

        testDefaults.shouldShowExpiredEntitlementMessaging = Self.showsAlertAndNotification
        XCTAssertEqual(testDefaults.shouldShowExpiredEntitlementMessaging, Self.showsAlertAndNotification)

        testDefaults.shouldShowExpiredEntitlementMessaging = Self.showsAlertOnly
        XCTAssertEqual(testDefaults.shouldShowExpiredEntitlementMessaging, Self.showsAlertOnly)

        testDefaults.shouldShowExpiredEntitlementMessaging = Self.showsNotificationOnly
        XCTAssertEqual(testDefaults.shouldShowExpiredEntitlementMessaging, Self.showsNotificationOnly)

        testDefaults.shouldShowExpiredEntitlementMessaging = Self.showsAlertAndNotification
        XCTAssertNotEqual(testDefaults.shouldShowExpiredEntitlementMessaging, Self.showsAlertAndNotification)

        testDefaults.shouldShowExpiredEntitlementMessaging = nil
        XCTAssertNil(testDefaults.shouldShowExpiredEntitlementMessaging)
    }

    func testShowingNotification() {
        let settings = VPNSettings(defaults: testDefaults)
        let wrappee = MockNotificationPresenter()
        let presenter = NetworkProtectionNotificationsPresenterTogglableDecorator(settings: settings, wrappee: wrappee)

        // Nothing to show
        presenter.showExpiredEntitlementNotification()
        XCTAssertNil(wrappee.message)

        // Queue one notification
        settings.apply(change: .setShouldShowExpiredEntitlementMessaging(Self.showsAlertAndNotification))

        // Show that queued notification
        presenter.showExpiredEntitlementNotification()
        XCTAssertEqual(wrappee.message, .entitlementExpired)
        wrappee.message = nil

        // Failed attempt to show another notification
        presenter.showExpiredEntitlementNotification()
        XCTAssertNil(wrappee.message)

        // Failed attempt to queue another notification
        settings.apply(change: .setShouldShowExpiredEntitlementMessaging(Self.showsAlertAndNotification))
        presenter.showExpiredEntitlementNotification()
        XCTAssertNil(wrappee.message)

        // Reset the queue before adding another notification
        settings.apply(change: .setShouldShowExpiredEntitlementMessaging(nil))
        settings.apply(change: .setShouldShowExpiredEntitlementMessaging(Self.showsAlertAndNotification))
        presenter.showExpiredEntitlementNotification()
        XCTAssertEqual(wrappee.message, .entitlementExpired)
    }
}

extension UserDefaults.ExpiredEntitlementMessaging {
    public override func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? UserDefaults.ExpiredEntitlementMessaging else { return false }
        return showsAlert == other.showsAlert && showsNotification == other.showsNotification
    }
}
