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
import Common
import os.log

public protocol SubscriptionCookieManaging {
    init(subscriptionManager: SubscriptionManager, currentCookieStore: @MainActor @escaping () -> HTTPCookieStore?, eventMapping: EventMapping<SubscriptionCookieManagerEvent>) async
    func refreshSubscriptionCookie() async
    func resetLastRefreshDate()

    var lastRefreshDate: Date? { get }
}

public final class SubscriptionCookieManager: SubscriptionCookieManaging {

    public static let cookieDomain = ".duckduckgo.com"
    public static let cookieName = "privacy_pro_access_token"

    private static let defaultRefreshTimeInterval: TimeInterval = .hours(4)

    private let subscriptionManager: SubscriptionManager
    private let currentCookieStore: @MainActor () -> HTTPCookieStore?
    private let eventMapping: EventMapping<SubscriptionCookieManagerEvent>

    public private(set) var lastRefreshDate: Date?
    private let refreshTimeInterval: TimeInterval

    convenience nonisolated public required init(subscriptionManager: SubscriptionManager,
                                                 currentCookieStore: @MainActor @escaping () -> HTTPCookieStore?,
                                                 eventMapping: EventMapping<SubscriptionCookieManagerEvent>) {
        self.init(subscriptionManager: subscriptionManager,
                  currentCookieStore: currentCookieStore,
                  eventMapping: eventMapping,
                  refreshTimeInterval: SubscriptionCookieManager.defaultRefreshTimeInterval)
    }

    nonisolated public required init(subscriptionManager: SubscriptionManager,
                                     currentCookieStore: @MainActor @escaping () -> HTTPCookieStore?,
                                     eventMapping: EventMapping<SubscriptionCookieManagerEvent>,
                                     refreshTimeInterval: TimeInterval) {
        self.subscriptionManager = subscriptionManager
        self.currentCookieStore = currentCookieStore
        self.eventMapping = eventMapping
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
                Logger.subscription.error("[SubscriptionCookieManager] Handle .accountDidSignIn - can't set the cookie, token is missing")
                eventMapping.fire(.errorHandlingAccountDidSignInTokenIsMissing)
                return
            }
            Logger.subscription.info("[SubscriptionCookieManager] Handle .accountDidSignIn - setting cookie")
           
            do {
                try await cookieStore.setSubscriptionCookie(for: accessToken)
                updateLastRefreshDateToNow()
            } catch {
                eventMapping.fire(.failedToSetSubscriptionCookie)
            }
        }
    }

    @objc private func handleAccountDidSignOut() {
        Task {
            guard let cookieStore = await currentCookieStore() else { return }
            guard let subscriptionCookie = await cookieStore.fetchCurrentSubscriptionCookie() else {
                Logger.subscription.error("[SubscriptionCookieManager] Handle .accountDidSignOut - can't delete the cookie, cookie is missing")
                eventMapping.fire(.errorHandlingAccountDidSignOutCookieIsMissing)
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
                do {
                    try await cookieStore.setSubscriptionCookie(for: accessToken)
                    eventMapping.fire(.subscriptionCookieRefreshedWithUpdate)
                } catch {
                    eventMapping.fire(.failedToSetSubscriptionCookie)
                }
            } else {
                Logger.subscription.info("[SubscriptionCookieManager] Refresh: Cookie exists and is up to date")
                return
            }
        } else {
            if let subscriptionCookie {
                Logger.subscription.info("[SubscriptionCookieManager] Refresh: No access token but old cookie exists, deleting it")
                await cookieStore.deleteCookie(subscriptionCookie)
                eventMapping.fire(.subscriptionCookieRefreshedWithDelete)
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

enum SubscriptionCookieManagerError: Error {
    case failedToCreateSubscriptionCookie
}


private extension HTTPCookieStore {

    func fetchCurrentSubscriptionCookie() async -> HTTPCookie? {
        await allCookies().first { $0.domain == SubscriptionCookieManager.cookieDomain && $0.name == SubscriptionCookieManager.cookieName }
    }

    func setSubscriptionCookie(for token: String) async throws {
        guard let cookie = HTTPCookie(properties: [
            .domain: SubscriptionCookieManager.cookieDomain,
            .path: "/",
            .expires: Date().addingTimeInterval(.days(365)),
            .name: SubscriptionCookieManager.cookieName,
            .value: token,
            .secure: true,
            .init(rawValue: "HttpOnly"): true
        ]) else {
            Logger.subscription.error("[HTTPCookieStore] Subscription cookie could not be created")
            assertionFailure("Subscription cookie could not be created")
            throw SubscriptionCookieManagerError.failedToCreateSubscriptionCookie
        }

        Logger.subscription.info("[HTTPCookieStore] Setting subscription cookie")
        await setCookie(cookie)
    }
}
