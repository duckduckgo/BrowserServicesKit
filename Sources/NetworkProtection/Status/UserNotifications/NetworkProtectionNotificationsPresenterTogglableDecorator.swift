//
//  NetworkProtectionNotificationsPresenterTogglableDecorator.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

final public class NetworkProtectionNotificationsPresenterTogglableDecorator: NetworkProtectionNotificationsPresenter {
    private let notificationSettingsStore: NetworkProtectionNotificationsSettingsStore
    private let wrappeePresenter: NetworkProtectionNotificationsPresenter

    public init(notificationSettingsStore: NetworkProtectionNotificationsSettingsStore, wrappee: NetworkProtectionNotificationsPresenter) {
        self.notificationSettingsStore = notificationSettingsStore
        self.wrappeePresenter = wrappee
    }

    public func showConnectedNotification(serverLocation: String?) {
        guard notificationSettingsStore.alertsEnabled else {
            return
        }
        wrappeePresenter.showConnectedNotification(serverLocation: serverLocation)
    }
    
    public func showReconnectingNotification() {
        guard notificationSettingsStore.alertsEnabled else {
            return
        }
        wrappeePresenter.showReconnectingNotification()
    }
    
    public func showConnectionFailureNotification() {
        guard notificationSettingsStore.alertsEnabled else {
            return
        }
        wrappeePresenter.showConnectionFailureNotification()
    }
    
    public func showSupersededNotification() {
        guard notificationSettingsStore.alertsEnabled else {
            return
        }
        wrappeePresenter.showSupersededNotification()
    }
    
    public func showTestNotification() {
        guard notificationSettingsStore.alertsEnabled else {
            return
        }
        wrappeePresenter.showTestNotification()
    }
}
