//
//  AppStoreAccountManagementFlow.swift
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
import StoreKit
import Common

@available(macOS 12.0, iOS 15.0, *)
public final class AppStoreAccountManagementFlow {

        public enum Error: Swift.Error {
            case noPastTransaction
            case authenticatingWithTransactionFailed
        }

    @discardableResult
    public static func refreshAuthTokenIfNeeded(subscriptionAppGroup: String) async -> Result<String, AppStoreAccountManagementFlow.Error> {
        os_log(.info, log: .subscription, "[AppStoreAccountManagementFlow] refreshAuthTokenIfNeeded")
        let accountManager = AccountManager(subscriptionAppGroup: subscriptionAppGroup)

        var authToken = accountManager.authToken ?? ""

        // Check if auth token if still valid
        if case let .failure(validateTokenError) = await AuthService.validateToken(accessToken: authToken) {
            os_log(.error, log: .subscription, "[AppStoreAccountManagementFlow] validateToken error: %{public}s", String(reflecting: validateTokenError))

            // In case of invalid token attempt store based authentication to obtain a new one
            guard let lastTransactionJWSRepresentation = await PurchaseManager.mostRecentTransaction() else { return .failure(.noPastTransaction) }

            switch await AuthService.storeLogin(signature: lastTransactionJWSRepresentation) {
            case .success(let response):
                if response.externalID == accountManager.externalID {
                    authToken = response.authToken
                    accountManager.storeAuthToken(token: authToken)
                }
            case .failure(let storeLoginError):
                os_log(.error, log: .subscription, "[AppStoreAccountManagementFlow] storeLogin error: %{public}s", String(reflecting: storeLoginError))
                return .failure(.authenticatingWithTransactionFailed)
            }
        }

        return .success(authToken)
    }
}
