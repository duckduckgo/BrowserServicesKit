//
//  SubscriptionCookieManager.swift
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

import Foundation
import WebKit
import os.log

public protocol HTTPCookieStore {
    func allCookies() async -> [HTTPCookie]
    func setCookie(_ cookie: HTTPCookie) async
    func deleteCookie(_ cookie: HTTPCookie) async
}

extension WKHTTPCookieStore: HTTPCookieStore {}

public protocol SubscriptionCookieManaging {
    init(subscriptionManager: SubscriptionManager, currentCookieStore: @MainActor @escaping () -> HTTPCookieStore?) async
    func refreshSubscriptionCookie() async
    func resetLastRefreshDate()
}

public final class SubscriptionCookieManager: SubscriptionCookieManaging {

    public static let cookieDomain = "duckduckgo.com"
    public static let cookieName = "privacy_pro_access_token"

    private static let defaultRefreshTimeInterval: TimeInterval = .seconds(10) // TODO: change the default to e.g. 4h

    private let subscriptionManager: SubscriptionManager
    private let currentCookieStore: @MainActor () -> HTTPCookieStore?

    private var lastRefreshDate: Date?
    private let refreshTimeInterval: TimeInterval

    convenience nonisolated public required init(subscriptionManager: SubscriptionManager,
                                                 currentCookieStore: @MainActor @escaping () -> HTTPCookieStore?) {
        self.init(subscriptionManager: subscriptionManager,
                  currentCookieStore: currentCookieStore,
                  refreshTimeInterval: SubscriptionCookieManager.defaultRefreshTimeInterval)
    }

    nonisolated public required init(subscriptionManager: SubscriptionManager,
                                     currentCookieStore: @MainActor @escaping () -> HTTPCookieStore?,
                                     refreshTimeInterval: TimeInterval) {
        self.subscriptionManager = subscriptionManager
        self.currentCookieStore = currentCookieStore
        self.refreshTimeInterval = refreshTimeInterval

        registerForSubscriptionAccountManagerEvents()
    }

    private func registerForSubscriptionAccountManagerEvents() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAccountDidSignIn), name: .accountDidSignIn, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAccountDidSignOut), name: .accountDidSignOut, object: nil)
    }

    @objc private func handleAccountDidSignIn() {
        Task {
            guard let cookieStore = await currentCookieStore() else { return }
            guard let accessToken = subscriptionManager.accountManager.accessToken else {
                // TODO: Add error handling ".accountDidSignIn event but access token is missing"
                return
            }
            Logger.subscription.info("[SubscriptionCookieManager] Handle .accountDidSignIn - setting cookie")
            await cookieStore.setSubscriptionCookie(for: accessToken)
            updateLastRefreshDateToNow()
        }
    }

    @objc private func handleAccountDidSignOut() {
        Task {
            guard let cookieStore = await currentCookieStore() else { return }
            guard let subscriptionCookie = await cookieStore.fetchCurrentSubscriptionCookie() else {
                // TODO: Add error handling ".accountDidSignOut event but cookie is missing"
                return
            }
            Logger.subscription.info("[SubscriptionCookieManager] Handle .accountDidSignOut - deleting cookie")
            await cookieStore.deleteCookie(subscriptionCookie)
            updateLastRefreshDateToNow()
        }
    }

    public func refreshSubscriptionCookie() async {
        guard shouldRefreshSubscriptionCookie() else { return }
        guard let cookieStore = await currentCookieStore() else { return }

        Logger.subscription.info("[SubscriptionCookieManager] Refresh subscription cookie")
        updateLastRefreshDateToNow()

        let accessToken: String? = subscriptionManager.accountManager.accessToken
        let subscriptionCookie = await cookieStore.fetchCurrentSubscriptionCookie()

        if let accessToken {
            if subscriptionCookie == nil || subscriptionCookie?.value != accessToken {
                Logger.subscription.info("[SubscriptionCookieManager] Refresh: No cookie or one with different value")
                await cookieStore.setSubscriptionCookie(for: accessToken)
                // TODO: Pixel that refresh actually was required - fixed by updating the token
            } else {
                Logger.subscription.info("[SubscriptionCookieManager] Refresh: Cookie exists and is up to date")
                return
            }
        } else {
            if let subscriptionCookie {
                Logger.subscription.info("[SubscriptionCookieManager] Refresh: No access token but old cookie exists, deleting it")
                await cookieStore.deleteCookie(subscriptionCookie)
                // TODO: Pixel that refresh actually was required - fixed by deleting the token
            }
        }
    }

    private func shouldRefreshSubscriptionCookie() -> Bool {
        switch lastRefreshDate {
        case .none:
            return true
        case .some(let previousLastRefreshDate):
            return previousLastRefreshDate.timeIntervalSinceNow < -refreshTimeInterval
        }
    }

    private func updateLastRefreshDateToNow() {
        lastRefreshDate = Date()
    }

    public func resetLastRefreshDate() {
        lastRefreshDate = nil
    }
}

private extension HTTPCookieStore {

    func fetchCurrentSubscriptionCookie() async -> HTTPCookie? {
        await allCookies().first { $0.domain == SubscriptionCookieManager.cookieDomain && $0.name == SubscriptionCookieManager.cookieName }
    }

    func setSubscriptionCookie(for token: String) async {
        guard let cookie = HTTPCookie(properties: [
            .domain: SubscriptionCookieManager.cookieDomain,
            .path: "/",
            .expires: Date().addingTimeInterval(.days(365)),
            .name: SubscriptionCookieManager.cookieName,
            .value: token,
            .secure: true,
            .init(rawValue: "HttpOnly"): true
        ]) else {
            // TODO: Add error handling "Failed to make a subscription cookie"
            Logger.subscription.error("[HTTPCookieStore] Subscription cookie could not be created")
            assertionFailure("Subscription cookie could not be created")
            return
        }

        Logger.subscription.info("[HTTPCookieStore] Setting subscription cookie")
        await setCookie(cookie)
    }
}
