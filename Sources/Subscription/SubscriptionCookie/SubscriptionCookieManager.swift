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

public protocol HTTPCookieStore {
    func allCookies() async -> [HTTPCookie]
    func setCookie(_ cookie: HTTPCookie) async
    func deleteCookie(_ cookie: HTTPCookie) async
}

extension WKHTTPCookieStore: HTTPCookieStore {}

public protocol SubscriptionCookieManaging {
    init(subscriptionManager: SubscriptionManager, currentCookieStore: @MainActor @escaping () -> HTTPCookieStore) async
    func refreshSubscriptionCookie() async
    func testCookies() async
}

public final class SubscriptionCookieManager: SubscriptionCookieManaging {

    public static let cookieDomain = "duckduckgo.com"
    public static let cookieName = "privacy_pro_access_token"

    private static let defaultRefreshTimeInterval: TimeInterval = .seconds(10) // TODO: change the default to e.g. 4h

    private let subscriptionManager: SubscriptionManager
    private let currentCookieStore: @MainActor () -> HTTPCookieStore

    private var lastRefreshDate: Date?
    private let refreshTimeInterval: TimeInterval

    convenience nonisolated public required init(subscriptionManager: SubscriptionManager,
                                                 currentCookieStore: @MainActor @escaping () -> HTTPCookieStore) {
        self.init(subscriptionManager: subscriptionManager, 
                  currentCookieStore: currentCookieStore,
                  refreshTimeInterval: SubscriptionCookieManager.defaultRefreshTimeInterval)
    }

    nonisolated public required init(subscriptionManager: SubscriptionManager,
                                     currentCookieStore: @MainActor @escaping () -> HTTPCookieStore,
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
            guard let accessToken = subscriptionManager.accountManager.accessToken else {
                // TODO: Add error handling ".accountDidSignIn event but access token is missing"
                return
            }

            await setSubscriptionCookie(for: accessToken)
            print("[🍪 Cookie] Subscription sign in - setting cookie")
        }
    }

    @objc private func handleAccountDidSignOut() {
        Task {
            guard let subscriptionCookie = await fetchCurrentSubscriptionCookie() else {
                // TODO: Add error handling ".accountDidSignOut event but cookie is missing"
                return
            }

            await currentCookieStore().deleteCookie(subscriptionCookie)
            await deleteSubscriptionCookie()
            print("[🍪 Cookie] Subscription sign out - removing cookie")
        }
    }

    public func refreshSubscriptionCookie() async {
        print("[🍪 Cookie] Refresh subscription cookie (last refresh date since now: \(lastRefreshDate?.timeIntervalSinceNow ?? 0.0)")
        guard shouldRefreshSubscriptionCookie() else { return }

//        let token = "Test(\(String(describing: Date()))"
//        let token = "TEST2"
        let accessToken: String? = subscriptionManager.accountManager.accessToken

        print("[🍪 Cookie] Token: \(accessToken ?? "<none>")")

        lastRefreshDate = Date()
        print("[🍪 Cookie] New last refresh date")

        if let accessToken {
            if let cookie = await fetchCurrentSubscriptionCookie(), cookie.value == accessToken {
                print("[🍪 Cookie] Current up to date")
                // Cookie present with proper value
                return
            } else {
                // Cookie not present or with different value
                print("[🍪 Cookie] Cookie not present or with different value")
                await setSubscriptionCookie(for: accessToken)

                // TODO: Pixel that refresh actually was required - fixed by updating the token
            }
        } else {
            // remove cookie
            await deleteSubscriptionCookie()

            // TODO: Pixel that refresh actually was required - fixed by deleting the token
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

    private func fetchCurrentSubscriptionCookie() async -> HTTPCookie? {
        let cookieStore = await currentCookieStore()
        var currentCookie: HTTPCookie?

        for cookie in await cookieStore.allCookies() {
            if cookie.domain == Self.cookieDomain && cookie.name == Self.cookieName {
                currentCookie = cookie
                break
            }
        }

        return currentCookie
    }

    private func setSubscriptionCookie(for token: String) async {
        guard let subscriptionCookie = makeSubscriptionCookie(for: token) else {
            // TODO: Add error handling "Failed to make a subscription cookie"
            return
        }

        print("[🍪 Cookie] Updating cookie")
        await currentCookieStore().setCookie(subscriptionCookie)
    }

    private func deleteSubscriptionCookie() async {
        guard let cookie = await fetchCurrentSubscriptionCookie() else {
            // Not really an error
            // Add error handling "Tried to delete subscription cookie but it was not present"
            return
        }

        await currentCookieStore().deleteCookie(cookie)
        print("[🍪 Cookie] Deleting cookie")
    }

    private func makeSubscriptionCookie(for token: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: Self.cookieDomain,
            .path: "/",
            .expires: Date().addingTimeInterval(.days(365)),
            .name: Self.cookieName,
            .value: token,
            .secure: true,
            .init(rawValue: "HttpOnly"): true
        ])
    }

    public func testCookies() async {
        print("[🍪 testCookie] Test cookies ================= ")
        let cookieStore = await currentCookieStore()

        for cookie in await cookieStore.allCookies() {
            print(" [🍪 testCookie]  Cookie: \(cookie.domain) \(cookie.name)")
            if cookie.domain == Self.cookieDomain {
                print("  \(cookie.debugDescription.replacingOccurrences(of: "\n", with: "; "))")
            }
        }
        print("[🍪 testCookie] ============================== ")
    }
}
