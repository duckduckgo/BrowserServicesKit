//
//  SecureVaultManager.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Combine
import os

public enum AutofillType {
    case password
    case card
    case identity
}

public protocol SecureVaultManagerDelegate: SecureVaultErrorReporting {

    func secureVaultManager(_: SecureVaultManager,
                            promptUserToStoreCredentials credentials: SecureVaultModels.WebsiteCredentials)

    func secureVaultManager(_: SecureVaultManager, didAutofill type: AutofillType, withObjectId objectId: Int64)
    
    func secureVaultManager(_: SecureVaultManager, didRequestAuthenticationWithCompletionHandler: @escaping (Bool) -> Void)
}

public class SecureVaultManager {

    public weak var delegate: SecureVaultManagerDelegate?

    public init() { }

}

// Later these catches should check if it is an auth error and call the delegate to ask for user authentication.
extension SecureVaultManager: AutofillSecureVaultDelegate {

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestAutoFillInitDataForDomain domain: String,
                                   completionHandler: @escaping ([SecureVaultModels.WebsiteAccount],
                                                                 [SecureVaultModels.Identity],
                                                                 [SecureVaultModels.CreditCard]) -> Void) {

        do {
            let vault = try SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
            let accounts = try vault.accountsFor(domain: domain)
            let identities = try vault.identities()
            let cards = try vault.creditCards()

            completionHandler(accounts, identities, cards)
        } catch {
            os_log(.error, "Error requesting autofill init data: %{public}@", error.localizedDescription)
            completionHandler([], [], [])
        }
    }

    public func autofillUserScript(_: AutofillUserScript, didRequestPasswordManagerForDomain domain: String) {
        // no-op at this point
    }

    public func autofillUserScript(_: AutofillUserScript, didRequestStoreCredentialsForDomain domain: String, username: String, password: String) {
        guard let passwordData = password.data(using: .utf8) else { return }

        do {

            if let account = try SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
                .accountsFor(domain: domain)
                .first(where: { $0.username == username }) {

                let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
                delegate?.secureVaultManager(self, promptUserToStoreCredentials: credentials)

            } else {

                let account = SecureVaultModels.WebsiteAccount(username: username, domain: domain)
                let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
                delegate?.secureVaultManager(self, promptUserToStoreCredentials: credentials)

            }
        } catch {
            os_log(.error, "Error storing accounts: %{public}@", error.localizedDescription)
        }

    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestAccountsForDomain domain: String,
                                   completionHandler: @escaping ([SecureVaultModels.WebsiteAccount]) -> Void) {

        do {
            completionHandler(try SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
                                .accountsFor(domain: domain))
        } catch {
            os_log(.error, "Error requesting accounts: %{public}@", error.localizedDescription)
            completionHandler([])
        }

    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestCredentialsForAccount accountId: Int64,
                                   completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?) -> Void) {

        do {
            completionHandler(try SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
                                .websiteCredentialsFor(accountId: accountId))
            delegate?.secureVaultManager(self, didAutofill: .password, withObjectId: accountId)
        } catch {
            os_log(.error, "Error requesting credentials: %{public}@", error.localizedDescription)
            completionHandler(nil)
        }

    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestCreditCardWithId creditCardId: Int64,
                                   completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
        do {
            let card = try SecureVaultFactory.default.makeVault(errorReporter: self.delegate).creditCardFor(id: creditCardId)

            delegate?.secureVaultManager(self, didRequestAuthenticationWithCompletionHandler: { authenticated in
                if authenticated {
                    completionHandler(card)
                } else {
                    completionHandler(nil)
                }
            })
            
            delegate?.secureVaultManager(self, didAutofill: .card, withObjectId: creditCardId)
        } catch {
            os_log(.error, "Error requesting credit card: %{public}@", error.localizedDescription)
            completionHandler(nil)
        }
    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestIdentityWithId identityId: Int64,
                                   completionHandler: @escaping (SecureVaultModels.Identity?) -> Void) {
        do {
            completionHandler(try SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
                                .identityFor(id: identityId))
            delegate?.secureVaultManager(self, didAutofill: .identity, withObjectId: identityId)
        } catch {
            os_log(.error, "Error requesting identity: %{public}@", error.localizedDescription)
            completionHandler(nil)
        }
    }

}
