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

public struct AutofillData {
    public let identity: SecureVaultModels.Identity?
    public let credentials: SecureVaultModels.WebsiteCredentials?
    public let creditCard: SecureVaultModels.CreditCard?
}

public protocol SecureVaultManagerDelegate: SecureVaultErrorReporting {

    func secureVaultManager(_: SecureVaultManager, promptUserToStoreAutofillData data: AutofillData)

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
    
    /// Receives each of the types of data that the Autofill script has detected, and determines whether the user should be prompted to save them.
    /// This involves checking each proposed object to determine whether it already exists in the store.
    /// Currently, only one new type of data is presented to the user, but that decision is handled client-side so that it's easier to adapt in the future when multiple types are presented at once.
    public func autofillUserScript(_: AutofillUserScript, didRequestStoreDataForDomain domain: String, data: AutofillUserScript.DetectedAutofillData) {
        do {
            let vault = try SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
            
            // Determine if the identity should be sent to the client app:

            var proposedIdentity: SecureVaultModels.Identity?
            
            if let identity = data.identity, try vault.existingIdentityForAutofill(matching: identity) == nil {
                proposedIdentity = identity
            }
            
            // Determine if the credentials should be sent to the client app:
            
            var proposedCredentials: SecureVaultModels.WebsiteCredentials?

            if let credentials = data.credentials, let passwordData = credentials.password.data(using: .utf8) {
                if let account = try SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
                    .accountsFor(domain: domain)
                    .first(where: { $0.username == credentials.username }) {
                    proposedCredentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
                } else {
                    let account = SecureVaultModels.WebsiteAccount(username: credentials.username ?? "", domain: domain)
                    proposedCredentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
                }
            }
            
            // Determine if the payment method should be sent to the client app:
            
            var proposedCard: SecureVaultModels.CreditCard?
            
            if let card = data.creditCard, try vault.existingCardForAutofill(matching: card) == nil {
                proposedCard = card
            }
            
            // Assemble data and send to the delegate:
            
            let autofillData = AutofillData(identity: proposedIdentity, credentials: proposedCredentials, creditCard: proposedCard)
            delegate?.secureVaultManager(self, promptUserToStoreAutofillData: autofillData)
        } catch {
            os_log(.error, "Error storing data: %{public}@", error.localizedDescription)
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
