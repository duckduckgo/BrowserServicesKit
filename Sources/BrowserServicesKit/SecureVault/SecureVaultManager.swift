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
import Common

public enum AutofillType {
    case password
    case card
    case identity
}

public struct AutofillData {
    public let identity: SecureVaultModels.Identity?
    public let credentials: SecureVaultModels.WebsiteCredentials?
    public let creditCard: SecureVaultModels.CreditCard?
    public var automaticallySavedCredentials: Bool
}

public protocol SecureVaultManagerDelegate: SecureVaultErrorReporting {
    
    func secureVaultManagerIsEnabledStatus(_: SecureVaultManager) -> Bool

    func secureVaultManager(_: SecureVaultManager,
                            promptUserToStoreAutofillData data: AutofillData,
                            withTrigger trigger: AutofillUserScript.GetTriggerType?)

    func secureVaultManager(_: SecureVaultManager,
                            promptUserToAutofillCredentialsForDomain domain: String,
                            withAccounts accounts: [SecureVaultModels.WebsiteAccount],
                            withTrigger trigger: AutofillUserScript.GetTriggerType,
                            completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void)

    func secureVaultManager(_: SecureVaultManager,
                            promptUserWithGeneratedPassword password: String,
                            completionHandler: @escaping (Bool) -> Void)

    func secureVaultManager(_: SecureVaultManager, didAutofill type: AutofillType, withObjectId objectId: String)

    // swiftlint:disable:next identifier_name
    func secureVaultManager(_: SecureVaultManager, didRequestAuthenticationWithCompletionHandler: @escaping (Bool) -> Void)

    func secureVaultManager(_: SecureVaultManager, didRequestCreditCardsManagerForDomain domain: String)

    func secureVaultManager(_: SecureVaultManager, didRequestIdentitiesManagerForDomain domain: String)

    func secureVaultManager(_: SecureVaultManager, didRequestPasswordManagerForDomain domain: String)

    func secureVaultManager(_: SecureVaultManager, didReceivePixel: AutofillUserScript.JSPixel)

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

    // This property can be removed once all platforms will search for partial account matches as the default expected behaviour.
    private let includePartialAccountMatches: Bool

    public let tld: TLD?

    // Keeps track of partial account created from autogenerated credentials (Private Email + Pwd)
    public var autosaveAccount: SecureVaultModels.WebsiteAccount?

    // Keeps track of autogenerated data in forms
    public var autogeneratedUserName: Bool = false
    public var autogeneratedPassword: Bool = false
    public var autogeneratedCredentials: Bool {
        return autogeneratedUserName || autogeneratedPassword
    }

    public lazy var autofillWebsiteAccountMatcher: AutofillWebsiteAccountMatcher? = {
        guard let tld = tld else { return nil }
        return AutofillWebsiteAccountMatcher(autofillUrlMatcher: AutofillDomainNameUrlMatcher(),
                                             tld: tld)
    }()

    public init(vault: SecureVault? = nil,
                passwordManager: PasswordManager? = nil,
                includePartialAccountMatches: Bool = false,
                tld: TLD? = nil) {
        self.vault = vault
        self.passwordManager = passwordManager
        self.includePartialAccountMatches = includePartialAccountMatches
        self.tld = tld
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

            getAccounts(for: domain, from: vault, or: passwordManager, withPartialMatches: includePartialAccountMatches) { [weak self] accounts, error in
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

    public func autofillUserScript(_: AutofillUserScript, didRequestCreditCardsManagerForDomain domain: String) {
        delegate?.secureVaultManager(self, didRequestCreditCardsManagerForDomain: domain)
    }
    
    public func autofillUserScript(_: AutofillUserScript, didRequestIdentitiesManagerForDomain domain: String) {
        delegate?.secureVaultManager(self, didRequestIdentitiesManagerForDomain: domain)
    }

    public func autofillUserScript(_: AutofillUserScript, didRequestPasswordManagerForDomain domain: String) {
        delegate?.secureVaultManager(self, didRequestPasswordManagerForDomain: domain)
    }

    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestStoreDataForDomain domain: String,
                                   data: AutofillUserScript.DetectedAutofillData) {
        do {

            var autofilldata = data
            let vault = try? self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
            var autoSavedCredentials: SecureVaultModels.WebsiteCredentials?            
            
            // If the user navigated away from current domain
            if domain != autosaveAccount?.domain {
                autogeneratedUserName = false
                autogeneratedPassword = false                
                autosaveAccount = nil                
            }
            
            // Validate the existing account exists and matches the domain and fetch the credentials
            if let stringId = autosaveAccount?.id,
               let id = Int64(stringId),
               let credentials =  try? vault?.websiteCredentialsFor(accountId: id) {
                autoSavedCredentials = credentials
            } else {
                autosaveAccount = nil
            }

            if autofilldata.trigger == .emailProtection {
                autogeneratedUserName = data.credentials?.autogenerated ?? false
            }

            if autofilldata.trigger == .passwordGeneration {
                autogeneratedPassword = data.credentials?.autogenerated ?? false
            }

            // Account for cases when the user has manually changed an autogenerated password or private email
            if autofilldata.trigger == .formSubmission {
                if autosaveAccount != nil, let credentials = autoSavedCredentials {

                    let existingUsername = credentials.account.username
                    let existingPassword =  String(decoding:  credentials.password, as: UTF8.self)
                    let submittedUserName = data.credentials?.username
                    let submittedPassword = data.credentials?.password

                    // If both the password or username are different from the ones autosaved,
                    // it means the user has changed them, so we should not autosave
                    if (existingPassword != submittedPassword && submittedPassword != "") &&
                        (existingUsername != submittedUserName && submittedUserName != "") {
                        autogeneratedUserName = false
                        autogeneratedPassword = false
                    }

                }
            }

            autofilldata.credentials?.autogenerated = autogeneratedCredentials
            let shouldSilentlySave = autogeneratedCredentials && autofilldata.trigger != .formSubmission

            if !autogeneratedCredentials && data.trigger == .formSubmission {
                if let stringId = autosaveAccount?.id, let id = Int64(stringId) {
                    try? vault?.deleteWebsiteCredentialsFor(accountId:id)
                    autosaveAccount = nil
                }
            }
            
            try storeOrUpdateAutogeneratedCredentials(domain: domain, autofillData: autofilldata)

            // Update/Prompt in 3rd party password manager
            if let passwordManager = passwordManager, passwordManager.isEnabled {
                if !shouldSilentlySave {
                    let dataToPrompt = try existingEntries(for: domain, autofillData: autofilldata)
                    delegate?.secureVaultManager(self, promptUserToStoreAutofillData: dataToPrompt, withTrigger: data.trigger)
                    autosaveAccount = nil
                }
                return
            }

            // Prompt or notify on form submissions and clean any partial accounts for this instance (tab)
            if !shouldSilentlySave {
                var dataToPrompt = try existingEntries(for: domain, autofillData: autofilldata)

                // On form submissions use the local value for autogenerated credentials
                // In this case, the JS field should be treated more like "form has some autofilled data"
                if autofilldata.trigger == .formSubmission {
                    dataToPrompt.automaticallySavedCredentials = autogeneratedCredentials
                }
                delegate?.secureVaultManager(self, promptUserToStoreAutofillData: dataToPrompt, withTrigger: autofilldata.trigger)
            }

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
            getAccounts(for: domain, from: vault,
                        or: passwordManager,
                        withPartialMatches: includePartialAccountMatches) { [weak self] accounts, error in
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

            getAccounts(for: domain,
                        from: vault,
                        or: passwordManager,
                        withPartialMatches: includePartialAccountMatches) { [weak self] accounts, error in
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

    public func autofillUserScriptDidOfferGeneratedPassword(_: AutofillUserScript, password: String, completionHandler: @escaping (Bool) -> Void) {
        delegate?.secureVaultManager(self,
                                     promptUserWithGeneratedPassword: password) { useGeneratedPassword in
            completionHandler(useGeneratedPassword)
        }
    }
    
    public func autofillUserScript(_: AutofillUserScript, didSendPixel pixel: AutofillUserScript.JSPixel) {
        delegate?.secureVaultManager(self, didReceivePixel: pixel)
    }

    /// Stores autogenerated credentials sent by the AutofillUserScript, or updates an existing row in the database if credentials already exist.
    func storeOrUpdateAutogeneratedCredentials(domain: String, autofillData: AutofillUserScript.DetectedAutofillData) throws {

        guard autogeneratedCredentials,
                let credentials = autofillData.credentials else {
            os_log("Did not meet conditions for silently saving autogenerated credentials, returning early", log: .passwordManager)
            return
        }
        
        let user: String = credentials.username ??  ""
        let pass: String = credentials.password ?? ""
                
        let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
        let accounts = try vault.accountsFor(domain: domain)
        var currentAccount: SecureVaultModels.WebsiteAccount

        // Grab an existing autosave account (if any)
        if let account = autosaveAccount, account.domain == domain {
            currentAccount = account

        // Find an existing account in the vault
        } else if let account = accounts.first(where: { $0.username == user }) {
            currentAccount = account

        // Create an new account
        } else {
            currentAccount = createAccount(vault: vault, username: user,
                                                 password: Data((pass).utf8),
                                                 domain: domain)
        }

        if let id = currentAccount.id {

            // Update password if provided
            let pwd = credentials.password ?? ""
            var pwdData: Data
            if pwd == "" {
                let credentials = try? vault.websiteCredentialsFor(accountId: id)
                pwdData = credentials?.password ?? Data()
            } else {
                pwdData = Data(pwd.utf8)
            }

            // Update username if provided
            if user != "" {
                currentAccount.username = user
            }

            // Save
            try vault.storeWebsiteCredentials(SecureVaultModels.WebsiteCredentials(account: currentAccount, password: pwdData))
        }

        // Update the autosave account with changes
        autosaveAccount = currentAccount

    }

    private func createAccount(vault: SecureVault, username: String, password: Data, domain: String) -> SecureVaultModels.WebsiteAccount {
        var account = SecureVaultModels.WebsiteAccount(username: username, domain: domain)
        account.id = try? String(vault.storeWebsiteCredentials(SecureVaultModels.WebsiteCredentials(account: account, password: password)))
        return account
    }

    func existingEntries(for domain: String,
                         autofillData: AutofillUserScript.DetectedAutofillData
    ) throws -> AutofillData {
        let vault = try self.vault ?? SecureVaultFactory.default.makeVault(errorReporter: self.delegate)
        
        let proposedIdentity = try existingIdentity(with: autofillData, vault: vault)
        let proposedCredentials: SecureVaultModels.WebsiteCredentials?
        if let passwordManager = passwordManager, passwordManager.isEnabled {
            proposedCredentials = existingCredentialsInPasswordManager(with: autofillData,
                                                                       domain: domain,
                                                                       vault: vault)
        } else {
            proposedCredentials = try existingCredentials(with: autofillData,
                                                          domain: domain,
                                                          vault: vault)
        }

        let proposedCard = try existingPaymentMethod(with: autofillData, vault: vault)
        
        return AutofillData(identity: proposedIdentity,
                            credentials: proposedCredentials,
                            creditCard: proposedCard,
                            automaticallySavedCredentials: autofillData.hasAutogeneratedCredentials)
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

        guard let credentials = autofillData.credentials,
            let passwordData = credentials.password?.data(using: .utf8) else {
            return nil
        }
        
        guard let accounts = try? vault.accountsFor(domain: domain),
              // Matching account (username) or account with empty username for domain
              var account = accounts.first(where: { $0.username == credentials.username || $0.username == "" }) else {
                
                // No existing credentials found.  This is a new entry
                let account = SecureVaultModels.WebsiteAccount(username: credentials.username ?? "", domain: domain)
                return SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)

        }

        guard let existingAccountId = account.id,
              let existingCredentials = try vault.websiteCredentialsFor(accountId: existingAccountId) else {
            return nil
        }

        // Prompt to save on submit autogenerated credentials OR user input that change the existing password
        if autofillData.hasAutogeneratedCredentials ||
            (!autofillData.hasAutogeneratedCredentials && existingCredentials.password != passwordData) {

            // If the previously saved username was empty, default to the submitted one
            if existingCredentials.account.username == "" {
                account.username = autofillData.credentials?.username ?? ""
            }

            return SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
        }

        // Prompt to update the login on submit when previous username was empty (the was a partial password account)
        if existingCredentials.account.username == "" {
            account.username = autofillData.credentials?.username ?? ""
            return SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
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
                             withPartialMatches: Bool = false,
                             completion: @escaping ([SecureVaultModels.WebsiteAccount], Error?) -> ()) {
        if let passwordManager = passwordManager,
           passwordManager.isEnabled {
            passwordManager.accountsFor(domain: domain, completion: completion)
        } else {
            do {
                if withPartialMatches {
                    guard let currentUrlComponents = AutofillDomainNameUrlMatcher().normalizeSchemeForAutofill(domain),
                          let tld = tld,
                          let eTLDplus1 = currentUrlComponents.eTLDplus1(tld: tld)
                    else {
                        completion([], nil)
                        return
                    }
                    let accounts = try vault.accountsWithPartialMatchesFor(eTLDplus1: eTLDplus1)
                    completion(accounts, nil)
                } else {
                    let accounts = try vault.accountsFor(domain: domain)
                    completion(accounts, nil)
                }
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
                                                      vault: SecureVault) -> SecureVaultModels.WebsiteCredentials? {
        guard let passwordManager = passwordManager, passwordManager.isEnabled else {
            return nil
        }

        guard let credentials = autofillData.credentials,
              let passwordData = credentials.password?.data(using: .utf8) else {
            return nil
        }

        guard let existingCredentials = passwordManager.cachedWebsiteCredentialsFor(domain: domain,
                                                                                    username: credentials.username ?? "") else {
            // No existing credentials found and not auto-generated, so return a new entry
            let account = SecureVaultModels.WebsiteAccount(username: credentials.username ?? "", domain: domain)
            return SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)

        }

        // Prompt to save on submit autogenerated credentials OR user input that change the existing password
        if autofillData.hasAutogeneratedCredentials || (!autofillData.hasAutogeneratedCredentials && existingCredentials.password != passwordData) {
            return SecureVaultModels.WebsiteCredentials(account: existingCredentials.account, password: passwordData)
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
