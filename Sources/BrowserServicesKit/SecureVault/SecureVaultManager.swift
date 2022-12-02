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
    public let automaticallySavedCredentials: Bool
}

public protocol SecureVaultManagerDelegate: SecureVaultErrorReporting {
    
    func secureVaultManagerIsEnabledStatus(_: SecureVaultManager) -> Bool

    func secureVaultManager(_: SecureVaultManager, promptUserToStoreAutofillData data: AutofillData)
    
    func secureVaultManager(_: SecureVaultManager,
                            promptUserToAutofillCredentialsForDomain domain: String,
                            withAccounts accounts: [SecureVaultModels.WebsiteAccount],
                            withTrigger trigger: AutofillUserScript.GetTriggerType,
                            completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void)

    func secureVaultManagerShouldAutomaticallyUpdateCredentialsWithoutUsername(_: SecureVaultManager) -> Bool

    func secureVaultManager(_: SecureVaultManager, didAutofill type: AutofillType, withObjectId objectId: String)

    // swiftlint:disable:next identifier_name
    func secureVaultManager(_: SecureVaultManager, didRequestAuthenticationWithCompletionHandler: @escaping (Bool) -> Void)

}

public protocol PasswordManager: AnyObject {

    var isEnabled: Bool { get }
    var name: String { get }
    var isLocked: Bool { get }

    func accountsFor(domain: String, completion: @escaping ([SecureVaultModels.WebsiteAccount], Error?) -> Void)
    func cachedAccountsFor(domain: String) -> [SecureVaultModels.WebsiteAccount]
    func cachedWebsiteCredentialsFor(domain: String, username: String) -> SecureVaultModels.WebsiteCredentials?
    func websiteCredentialsFor(accountId: String, completion: @escaping (SecureVaultModels.WebsiteCredentials?, Error?) -> Void)
    func websiteCredentialsFor(domain: String, completion: @escaping ([SecureVaultModels.WebsiteCredentials], Error?) -> Void)

    func askToUnlock(completionHandler: @escaping () -> Void)

}

public class SecureVaultManager {

    public weak var delegate: SecureVaultManagerDelegate?
    
    private let vault: SecureVault?

    // Third party password manager
    private let passwordManager: PasswordManager?

    public init(vault: SecureVault? = nil,
                passwordManager: PasswordManager? = nil) {
        self.vault = vault
        self.passwordManager = passwordManager
    }

}

// Later these catches should check if it is an auth error and call the delegate to ask for user authentication.
extension SecureVaultManager: AutofillSecureVaultDelegate {

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestAutoFillInitDataForDomain domain: String,
                                   completionHandler: @escaping ([SecureVaultModels.WebsiteAccount],
                                                                 [SecureVaultModels.Identity],
                                                                 [SecureVaultModels.CreditCard],
                                                                 SecureVaultModels.CredentialsProvider) -> Void) {

        do {
            guard let delegate = delegate, delegate.secureVaultManagerIsEnabledStatus(self) else {
                completionHandler([], [], [], credentialsProvider)
                return
            }
            let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
            let identities = try vault.identities()
            let cards = try vault.creditCards()

            getAccounts(for: domain, from: vault, or: passwordManager) { [weak self] accounts, error in
                guard let self = self else { return }
                if let error = error {
                    os_log(.error, "Error requesting autofill init data: %{public}@", error.localizedDescription)
                    completionHandler([], [], [], self.credentialsProvider)
                } else {
                    completionHandler(accounts, identities, cards, self.credentialsProvider)
                }
            }
        } catch {
            os_log(.error, "Error requesting autofill init data: %{public}@", error.localizedDescription)
            completionHandler([], [], [], credentialsProvider)
        }
    }

    public func autofillUserScript(_: AutofillUserScript, didRequestPasswordManagerForDomain domain: String) {
        // no-op at this point
    }
    
    /// Receives each of the types of data that the Autofill script has detected, and determines whether the user should be prompted to save them.
    /// This involves checking each proposed object to determine whether it already exists in the store.
    /// Currently, only one new type of data is presented to the user, but that decision is handled client-side so that it's easier to adapt in the future when multiple types are presented at once.
    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestStoreDataForDomain domain: String,
                                   data: AutofillUserScript.DetectedAutofillData) {
        do {

            if let passwordManager = passwordManager, passwordManager.isEnabled {
                let dataToPrompt = try existingEntries(for: domain, autofillData: data, automaticallySavedCredentials: false)
                delegate?.secureVaultManager(self, promptUserToStoreAutofillData: dataToPrompt)
                return
            }

            let automaticallySavedCredentials = try storeOrUpdateAutogeneratedCredentials(domain: domain, autofillData: data)

            if delegate?.secureVaultManagerShouldAutomaticallyUpdateCredentialsWithoutUsername(self) ?? false {
                try updateExistingCredentialsWithoutUsernameWithSubmittedValues(domain: domain, autofillData: data)
            }
            
            let dataToPrompt = try existingEntries(for: domain, autofillData: data, automaticallySavedCredentials: automaticallySavedCredentials)
            delegate?.secureVaultManager(self, promptUserToStoreAutofillData: dataToPrompt)
        } catch {
            os_log(.error, "Error storing data: %{public}@", error.localizedDescription)
        }
    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestAccountsForDomain domain: String,
                                   completionHandler: @escaping ([SecureVaultModels.WebsiteAccount],
                                                                 SecureVaultModels.CredentialsProvider) -> Void) {


        do {
            let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
            getAccounts(for: domain, from: vault, or: passwordManager) { [weak self] accounts, error in
                guard let self = self else { return }
                if let error = error {
                    os_log(.error, "Error requesting accounts: %{public}@", error.localizedDescription)
                    completionHandler([], self.credentialsProvider)
                } else {
                    completionHandler(accounts, self.credentialsProvider)
                }
            }
        } catch {
            os_log(.error, "Error requesting accounts: %{public}@", error.localizedDescription)
            completionHandler([], credentialsProvider)
        }

    }
            
    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestCredentialsForDomain domain: String,
                                   subType: AutofillUserScript.GetAutofillDataSubType,
                                   trigger: AutofillUserScript.GetTriggerType,
                                   completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?, SecureVaultModels.CredentialsProvider, RequestVaultCredentialsAction) -> Void) {
        do {
            let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)

            getAccounts(for: domain, from: vault, or: passwordManager) { [weak self] accounts, error in
                guard let self = self else { return }
                if let error = error {
                    os_log(.error, "Error requesting accounts: %{public}@", error.localizedDescription)
                    completionHandler(nil, self.credentialsProvider, .none)
                }

                let accounts = accounts.filter {
                    // don't show accounts without usernames if the user interacted with the 'username' field
                    if subType == .username && $0.username.isEmpty {
                        return false
                    }
                    return true
                }

                if accounts.count == 0 {
                    os_log(.debug, "Not showing the modal, no suitable accounts found")
                    completionHandler(nil, self.credentialsProvider, .none)
                    return
                }

                self.delegate?.secureVaultManager(self, promptUserToAutofillCredentialsForDomain: domain, withAccounts: accounts, withTrigger: trigger) { [weak self] account in
                    guard let self = self else { return }
                    guard let accountID = account?.id else {
                        completionHandler(nil, self.credentialsProvider, .none)
                        return
                    }

                    self.getCredentials(for: accountID, from: vault, or: self.passwordManager) { [weak self] credentials, error in
                        guard let self = self else { return }
                        if let error = error {
                            os_log(.error, "Error requesting credentials: %{public}@", error.localizedDescription)
                            completionHandler(nil, self.credentialsProvider, .none)
                        } else {
                            completionHandler(credentials, self.credentialsProvider, .fill)
                        }
                    }
                }
            }
        } catch {
            os_log(.error, "Error requesting accounts: %{public}@", error.localizedDescription)
            completionHandler(nil, credentialsProvider, .none)
        }
    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestCredentialsForAccount accountId: String,
                                   completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?, SecureVaultModels.CredentialsProvider) -> Void) {

        do {
            let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
            getCredentials(for: accountId, from: vault, or: self.passwordManager) { [weak self] credentials, error in
                guard let self = self else { return }
                if let error = error {
                    os_log(.error, "Error requesting credentials: %{public}@", error.localizedDescription)
                    completionHandler(nil, self.credentialsProvider)
                } else {
                    completionHandler(credentials, self.credentialsProvider)
                    self.delegate?.secureVaultManager(self, didAutofill: .password, withObjectId: accountId)
                }
            }
        } catch {
            os_log(.error, "Error requesting credentials: %{public}@", error.localizedDescription)
            completionHandler(nil, credentialsProvider)
        }

    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestCreditCardWithId creditCardId: Int64,
                                   completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
        do {
            let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
            let card = try vault.creditCardFor(id: creditCardId)

            delegate?.secureVaultManager(self, didRequestAuthenticationWithCompletionHandler: { authenticated in
                if authenticated {
                    completionHandler(card)
                } else {
                    completionHandler(nil)
                }
            })
            
            delegate?.secureVaultManager(self, didAutofill: .card, withObjectId: String(creditCardId))
        } catch {
            os_log(.error, "Error requesting credit card: %{public}@", error.localizedDescription)
            completionHandler(nil)
        }
    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestIdentityWithId identityId: Int64,
                                   completionHandler: @escaping (SecureVaultModels.Identity?) -> Void) {
        do {
            let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
            completionHandler(try vault.identityFor(id: identityId))

            delegate?.secureVaultManager(self, didAutofill: .identity, withObjectId: String(identityId))
        } catch {
            os_log(.error, "Error requesting identity: %{public}@", error.localizedDescription)
            completionHandler(nil)
        }
    }

    public func autofillUserScriptDidAskToUnlockCredentialsProvider(_: AutofillUserScript,
                                                                    andProvideCredentialsForDomain domain: String,
                                                                    completionHandler: @escaping ([SecureVaultModels.WebsiteCredentials],
                                                                                                  [SecureVaultModels.Identity],
                                                                                                  [SecureVaultModels.CreditCard],
                                                                                                  SecureVaultModels.CredentialsProvider) -> Void) {
        if let passwordManager = passwordManager, passwordManager.isEnabled {
            passwordManager.askToUnlock { [weak self] in
                passwordManager.websiteCredentialsFor(domain: domain) { [weak self] credentials, error in
                    guard let self = self else { return }
                    if let error = error {
                        os_log(.error, "Error requesting credentials: %{public}@", error.localizedDescription)
                        completionHandler([], [], [], self.credentialsProvider)
                    } else {
                        do {
                            let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
                            let identities = try vault.identities()
                            let cards = try vault.creditCards()
                            completionHandler(credentials, identities, cards, self.credentialsProvider)
                        } catch {
                            os_log(.error, "Error requesting identities or cards: %{public}@", error.localizedDescription)
                            completionHandler([], [], [], self.credentialsProvider)
                        }
                    }
                }
            }
        } else {
            completionHandler([], [], [], credentialsProvider)
        }
    }

    public func autofillUserScript(_: AutofillUserScript, didRequestCredentialsForDomain domain: String, completionHandler: @escaping ([SecureVaultModels.WebsiteCredentials], SecureVaultModels.CredentialsProvider) -> Void) {
        if let passwordManager = passwordManager, passwordManager.isEnabled {
            passwordManager.websiteCredentialsFor(domain: domain) { [weak self] credentials, error in
                guard let self = self else { return }
                if let error = error {
                    os_log(.error, "Error requesting credentials: %{public}@", error.localizedDescription)
                    completionHandler([], self.credentialsProvider)
                } else {
                    completionHandler(credentials, self.credentialsProvider)
                }
            }
        } else {
            // This method is necessary only when using a third party password manager
            assertionFailure("Not implemented")

            completionHandler([], credentialsProvider)
        }
    }

    
    /// Stores autogenerated credentials sent by the AutofillUserScript, or updates an existing row in the database if credentials already exist.
    /// The Secure Vault only stores one generated password for a domain, which is updated any time the user selects a new generated password.
    func storeOrUpdateAutogeneratedCredentials(domain: String, autofillData: AutofillUserScript.DetectedAutofillData) throws -> Bool {
        guard autofillData.hasAutogeneratedPassword,
              let autogeneratedCredentials = autofillData.credentials,
              !(autogeneratedCredentials.username?.isEmpty ?? true),
              let passwordData = autogeneratedCredentials.password.data(using: .utf8) else {
            os_log("Did not meet conditions for silently saving autogenerated credentials, returning early", log: .passwordManager)
            return false
        }

        let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
        let accounts = try vault.accountsFor(domain: domain)
        
        if accounts.contains(where: { account in account.username == autogeneratedCredentials.username }) {
            os_log("Tried to automatically save credentials for which an account already exists, returning early", log: .passwordManager)
            return false
        }
        
        // As a precaution, check whether an account exists with the matching generated password _and_ a non-nil username.
        // If so, then the user must have already saved the generated credentials and set a username.

        for account in accounts where !account.username.isEmpty {
            if let accountID = account.id,
               let credentialsForAccount = try vault.websiteCredentialsFor(accountId: accountID),
               credentialsForAccount.password == passwordData,
               account.username == autogeneratedCredentials.username ?? "" {
                os_log("Tried to save autogenerated password but it already exists, returning early", log: .passwordManager)
                return false
            }
        }
        
        let existingAccount = accounts.first(where: { $0.username == "" })
        var account = existingAccount ?? SecureVaultModels.WebsiteAccount(username: "", domain: domain)
        
        account.title = "Saved Password (\(domain))"
        let generatedPassword = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)

        os_log("Saving autogenerated password", log: .passwordManager)

        try vault.storeWebsiteCredentials(generatedPassword)
        
        return true
    }
    
    /// If credentials are sent via the AutofillUserScript, and there exists a credential row with empty username and matching password, then this function will update that credential row with the username.
    /// This can happen if the user saves a form with only a password when signing up for a service, then enters their own username and submits the form.
    func updateExistingCredentialsWithoutUsernameWithSubmittedValues(domain: String, autofillData: AutofillUserScript.DetectedAutofillData) throws {
        let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
        let accounts = try vault.accountsFor(domain: domain)

        guard let autofillCredentials = autofillData.credentials,
              let autofillCredentialsUsername = autofillCredentials.username,
              var existingAccount = accounts.first(where: { $0.username == "" }),
              let existingAccountID = existingAccount.id else {
            return
        }
        
        if accounts.contains(where: { $0.username == autofillCredentials.username }) {
            os_log("ERROR: Tried to save generated credentials with an existing username, prompt the user to update instead.", log: .passwordManager)
            return
        }

        let existingCredentials = try vault.websiteCredentialsFor(accountId: existingAccountID)

        guard let existingPasswordData = existingCredentials?.password,
              let autofillPasswordData = autofillCredentials.password.data(using: .utf8) else {
            return
        }
        
        // If true, then the existing generated password matches the credentials sent by the script, so update and save the difference.
        if existingPasswordData == autofillPasswordData {
            os_log("Found matching autogenerated credentials in Secure Vault, updating with username", log: .passwordManager)
            
            existingAccount.username = autofillCredentialsUsername
            existingAccount.title = nil // Remove the "Saved Password" title so that the UI uses the default title format
            
            let credentialsToSave = SecureVaultModels.WebsiteCredentials(account: existingAccount, password: autofillPasswordData)
            
            try vault.storeWebsiteCredentials(credentialsToSave)
        }
    }
    
    func existingEntries(for domain: String,
                         autofillData: AutofillUserScript.DetectedAutofillData,
                         automaticallySavedCredentials: Bool) throws -> AutofillData {
        let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
        
        let proposedIdentity = try existingIdentity(with: autofillData, vault: vault)
        let proposedCredentials: SecureVaultModels.WebsiteCredentials?
        if let passwordManager = passwordManager, passwordManager.isEnabled {
            proposedCredentials = existingCredentialsInPasswordManager(with: autofillData,
                                                                       domain: domain,
                                                                       automaticallySavedCredentials: automaticallySavedCredentials,
                                                                       vault: vault)
        } else {
            proposedCredentials = try existingCredentials(with: autofillData,
                                                          domain: domain,
                                                          automaticallySavedCredentials: automaticallySavedCredentials,
                                                          vault: vault)
        }

        let proposedCard = try existingPaymentMethod(with: autofillData, vault: vault)
        
        return AutofillData(identity: proposedIdentity,
                            credentials: proposedCredentials,
                            creditCard: proposedCard,
                            automaticallySavedCredentials: automaticallySavedCredentials)
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
                                     automaticallySavedCredentials: Bool,
                                     vault: SecureVault) throws -> SecureVaultModels.WebsiteCredentials? {
        if let credentials = autofillData.credentials, let passwordData = credentials.password.data(using: .utf8) {
            let accounts = try vault.accountsFor(domain: domain)
            if let account = accounts.first(where: { $0.username == credentials.username ?? "" }) {
                if let existingAccountID = account.id,
                   let existingCredentials = try vault.websiteCredentialsFor(accountId: existingAccountID),
                   existingCredentials.password == passwordData {
                    if automaticallySavedCredentials {
                        os_log("Found duplicate credentials which were just saved, notifying user", log: .passwordManager)
                        return SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
                    } else {
                        os_log("Found duplicate credentials which were previously saved, avoid notifying user", log: .passwordManager)
                        return nil
                    }
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

    // MARK: - Third-party password manager

    private var credentialsProvider: SecureVaultModels.CredentialsProvider {
        if let passwordManager = passwordManager,
           passwordManager.isEnabled,
           let name = SecureVaultModels.CredentialsProvider.Name(rawValue: passwordManager.name) {
            return SecureVaultModels.CredentialsProvider(name: name,
                                                         locked: passwordManager.isLocked)
        } else {
            return SecureVaultModels.CredentialsProvider(name: .duckduckgo, locked: false)
        }
    }

    private func getAccounts(for domain: String,
                     from vault: SecureVault,
                     or passwordManager: PasswordManager?,
                     completion: @escaping ([SecureVaultModels.WebsiteAccount], Error?) -> Void) {
        if let passwordManager = passwordManager,
           passwordManager.isEnabled {
            passwordManager.accountsFor(domain: domain, completion: completion)
        } else {
            do {
                let accounts = try vault.accountsFor(domain: domain)
                completion(accounts, nil)
            } catch {
                completion([], error)
            }
        }
    }

    private func getCredentials(for accountId: String,
                        from vault: SecureVault,
                        or passwordManager: PasswordManager?,
                        completion: @escaping (SecureVaultModels.WebsiteCredentials?, Error?) -> Void) {
        if let passwordManager = passwordManager,
           passwordManager.isEnabled {
            passwordManager.websiteCredentialsFor(accountId: accountId, completion: completion)
        } else {
            do {
                let credentials = try vault.websiteCredentialsFor(accountId: accountId)
                completion(credentials, nil)
            } catch {
                completion(nil, error)
            }
        }
    }


    private func existingCredentialsInPasswordManager(with autofillData: AutofillUserScript.DetectedAutofillData,
                                                      domain: String,
                                                      automaticallySavedCredentials: Bool,
                                                      vault: SecureVault) -> SecureVaultModels.WebsiteCredentials? {
        guard let passwordManager = passwordManager, passwordManager.isEnabled else {
            return nil
        }

        if let credentials = autofillData.credentials, let passwordData = credentials.password.data(using: .utf8) {
            if let existingCredentials = passwordManager.cachedWebsiteCredentialsFor(domain: domain, username: credentials.username ?? "") {
                if existingCredentials.password == passwordData {
                    if automaticallySavedCredentials {
                        os_log("Found duplicate credentials which were just saved, notifying user", log: .passwordManager)
                        return SecureVaultModels.WebsiteCredentials(account: existingCredentials.account, password: passwordData)
                    } else {
                        os_log("Found duplicate credentials which were previously saved, avoid notifying user", log: .passwordManager)
                        return nil
                    }
                } else {
                    os_log("Found existing credentials to update", log: .passwordManager)
                    return SecureVaultModels.WebsiteCredentials(account: existingCredentials.account, password: passwordData)
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

}

fileprivate extension SecureVault {

    func websiteCredentialsFor(accountId: String) throws -> SecureVaultModels.WebsiteCredentials? {
        guard let accountIdInt = Int64(accountId) else {
            assertionFailure("Bad account id format")
            return nil
        }

        return try websiteCredentialsFor(accountId: accountIdInt)
    }

}
