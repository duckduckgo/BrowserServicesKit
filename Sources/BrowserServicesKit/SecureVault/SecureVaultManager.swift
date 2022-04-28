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
    
    func secureVaultManager(_: SecureVaultManager,
                            promptUserToAutofillCredentialsForDomain domain: String,
                            withAccounts accounts: [SecureVaultModels.WebsiteAccount],
                            completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void)

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
            let dataToPrompt = try existingEntries(for: domain, autofillData: data)
            delegate?.secureVaultManager(self, promptUserToStoreAutofillData: dataToPrompt)
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
                                   didRequestCredentialsForDomain domain: String,
                                   completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?) -> Void) {
        do {
            let vault = try SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
            let accounts = try vault.accountsFor(domain: domain)
            delegate?.secureVaultManager(self, promptUserToAutofillCredentialsForDomain: domain, withAccounts: accounts) { account in
                guard let accountID = account?.id else {
                    completionHandler(nil)
                    return
                }
                
                do {
                    let credentials = try vault.websiteCredentialsFor(accountId: accountID)
                    completionHandler(credentials)
                } catch {
                    os_log(.error, "Error requesting credentials: %{public}@", error.localizedDescription)
                    completionHandler(nil)
                }
            }
        } catch {
            os_log(.error, "Error requesting accounts: %{public}@", error.localizedDescription)
            completionHandler(nil)
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
    
    func existingEntries(for domain: String, autofillData: AutofillUserScript.DetectedAutofillData) throws -> AutofillData {
        let vault = try SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
        
        let proposedIdentity = try existingIdentity(with: autofillData, vault: vault)
        let proposedCredentials = try existingCredentials(with: autofillData, domain: domain, vault: vault)
        let proposedCard = try existingPaymentMethod(with: autofillData, vault: vault)
        
        return AutofillData(identity: proposedIdentity, credentials: proposedCredentials, creditCard: proposedCard)
    }
    
    private func existingIdentity(with autofillData: AutofillUserScript.DetectedAutofillData,
                                  vault: SecureVault) throws -> SecureVaultModels.Identity? {
        if let identity = autofillData.identity, try vault.existingIdentityForAutofill(matching: identity) == nil {
            os_log("Got new identity/address to save", log: .passwordManager)
            return identity
        } else {
            os_log("No new identity/address found, avoid prompting user", log: .passwordManager)
            return nil
        }
    }
    
    private func existingCredentials(with autofillData: AutofillUserScript.DetectedAutofillData,
                                     domain: String,
                                     vault: SecureVault) throws -> SecureVaultModels.WebsiteCredentials? {
        if let credentials = autofillData.credentials, let passwordData = credentials.password.data(using: .utf8) {
            if let account = try vault
                .accountsFor(domain: domain)
                .first(where: { $0.username == credentials.username }) {
                
                if let existingAccountID = account.id,
                   let existingCredentials = try vault.websiteCredentialsFor(accountId: existingAccountID),
                   existingCredentials.password == passwordData {
                    os_log("Found duplicate credentials, avoid prompting user", log: .passwordManager)
                    return nil
                } else {
                    os_log("Found existing credentials to update", log: .passwordManager)
                    return SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
                }

            } else {
                os_log("Received new credentials to save", log: .passwordManager)
                let account = SecureVaultModels.WebsiteAccount(username: credentials.username ?? "", domain: domain)
                return SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
            }
        } else {
            os_log("No new credentials found, avoid prompting user", log: .passwordManager)
        }
        
        return nil
    }
    
    private func existingPaymentMethod(with autofillData: AutofillUserScript.DetectedAutofillData,
                                  vault: SecureVault) throws -> SecureVaultModels.CreditCard? {
        if let card = autofillData.creditCard, try vault.existingCardForAutofill(matching: card) == nil {
            os_log("Got new payment method to save", log: .passwordManager)
            return card
        } else {
            os_log("No new payment method found, avoid prompting user", log: .passwordManager)
            return nil
        }
    }

}
