//
//  MockNotificationPresenter.swift
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

@testable import NetworkProtection

public class MockNotificationPresenter: NetworkProtectionNotificationsPresenter {

    enum UserText: String {
        case someLocation
        case reconnecting
        case connectionFailed
        case superseded
        case test
        case entitlementExpired
    }

    var message: UserText?

    public func showConnectedNotification(serverLocation: String?) {
        message = .someLocation
    }

    public func showReconnectingNotification() {
        message = .reconnecting
    }

    public func showConnectionFailureNotification() {
        message = .connectionFailed
    }

    public func showSupersededNotification() {
        message = .superseded
    }

    public func showTestNotification() {
        message = .test
    }

    public func showExpiredEntitlementNotification() {
        message = .entitlementExpired
    }
}
