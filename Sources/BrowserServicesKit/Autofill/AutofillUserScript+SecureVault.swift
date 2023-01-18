//
//  AutofillUserScript+SecureVault.swift
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

import WebKit
import os
import Common
import UserScript

// swiftlint:disable file_length

public enum RequestVaultCredentialsAction: String, Codable {
    case none
    case fill
}

public protocol AutofillSecureVaultDelegate: AnyObject {

    func autofillUserScript(_: AutofillUserScript, didRequestAutoFillInitDataForDomain domain: String, completionHandler: @escaping (
        [SecureVaultModels.WebsiteAccount],
        [SecureVaultModels.Identity],
        [SecureVaultModels.CreditCard],
        SecureVaultModels.CredentialsProvider
    ) -> Void)

    func autofillUserScript(_: AutofillUserScript, didRequestPasswordManagerForDomain domain: String)
    func autofillUserScript(_: AutofillUserScript, didRequestStoreDataForDomain domain: String, data: AutofillUserScript.DetectedAutofillData)
    func autofillUserScript(_: AutofillUserScript, didRequestAccountsForDomain domain: String,
                            completionHandler: @escaping ([SecureVaultModels.WebsiteAccount], SecureVaultModels.CredentialsProvider) -> Void)
    func autofillUserScript(_: AutofillUserScript, didRequestCredentialsForDomain: String,
                            subType: AutofillUserScript.GetAutofillDataSubType,
                            trigger: AutofillUserScript.GetTriggerType,
                            completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?, SecureVaultModels.CredentialsProvider, RequestVaultCredentialsAction) -> Void)
    
    func autofillUserScript(_: AutofillUserScript, didRequestCredentialsForAccount accountId: String,
                            completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?, SecureVaultModels.CredentialsProvider) -> Void)
    func autofillUserScript(_: AutofillUserScript, didRequestCreditCardWithId creditCardId: Int64,
                            completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void)
    func autofillUserScript(_: AutofillUserScript, didRequestIdentityWithId identityId: Int64,
                            completionHandler: @escaping (SecureVaultModels.Identity?) -> Void)

    func autofillUserScriptDidAskToUnlockCredentialsProvider(_: AutofillUserScript,
                                                             andProvideCredentialsForDomain domain: String,
                                                             completionHandler: @escaping ([SecureVaultModels.WebsiteCredentials],
                                                                                           [SecureVaultModels.Identity],
                                                                                           [SecureVaultModels.CreditCard],
                                                                                           SecureVaultModels.CredentialsProvider) -> Void)
    func autofillUserScript(_: AutofillUserScript, didRequestCredentialsForDomain domain: String,
                            completionHandler: @escaping ([SecureVaultModels.WebsiteCredentials], SecureVaultModels.CredentialsProvider) -> Void)

    func autofillUserScript(_: AutofillUserScript, didSendPixel pixel: AutofillUserScript.JSPixel)

}

extension AutofillUserScript {

    // MARK: - Response Objects

    struct IdentityObject: Codable {
        let id: Int64
        let title: String

        let firstName: String?
        let middleName: String?
        let lastName: String?

        let birthdayDay: Int?
        let birthdayMonth: Int?
        let birthdayYear: Int?

        let addressStreet: String?
        let addressStreet2: String?
        let addressCity: String?
        let addressProvince: String?
        let addressPostalCode: String?
        let addressCountryCode: String?

        let phone: String?
        let emailAddress: String?

        static func from(identity: SecureVaultModels.Identity) -> IdentityObject? {
            guard let id = identity.id else { return nil }

            return IdentityObject(id: id,
                                  title: identity.title,
                                  firstName: identity.firstName,
                                  middleName: identity.middleName,
                                  lastName: identity.lastName,
                                  birthdayDay: identity.birthdayDay,
                                  birthdayMonth: identity.birthdayMonth,
                                  birthdayYear: identity.birthdayYear,
                                  addressStreet: identity.addressStreet,
                                  addressStreet2: identity.addressStreet2,
                                  addressCity: identity.addressCity,
                                  addressProvince: identity.addressProvince,
                                  addressPostalCode: identity.addressPostalCode,
                                  addressCountryCode: identity.addressCountryCode,
                                  phone: identity.homePhone, // Replace with single "phone number" column
                                  emailAddress: identity.emailAddress ?? "")
        }
    }

    struct CreditCardObject: Codable {
        let id: Int64
        let title: String
        let displayNumber: String

        let cardName: String?
        let cardNumber: String?
        let cardSecurityCode: String?
        let expirationMonth: Int?
        let expirationYear: Int?

        static func from(card: SecureVaultModels.CreditCard) -> CreditCardObject? {
            guard let id = card.id else { return nil }

            return CreditCardObject(id: id,
                                    title: card.title,
                                    displayNumber: card.displayName,
                                    cardName: card.cardholderName,
                                    cardNumber: card.cardNumber,
                                    cardSecurityCode: card.cardSecurityCode,
                                    expirationMonth: card.expirationMonth,
                                    expirationYear: card.expirationYear)
        }

        /// Provides a minimal summary of the card, suitable for presentation in the credit card selection list. This intentionally omits secure data, such as card number and cardholder name.
        static func autofillInitializationValueFrom(card: SecureVaultModels.CreditCard) -> CreditCardObject? {
            guard let id = card.id else { return nil }

            return CreditCardObject(id: id,
                                    title: card.title,
                                    displayNumber: card.displayName,
                                    cardName: nil,
                                    cardNumber: nil,
                                    cardSecurityCode: nil,
                                    expirationMonth: nil,
                                    expirationYear: nil)
        }
    }

    struct CredentialObject: Codable {
        let id: String
        let username: String
        let credentialsProvider: String?
    }
    
    // MARK: - Requests
    
    public struct IncomingCredentials: Equatable {

        private enum Constants {
            static let credentialsKey = "credentials"
            static let usernameKey = "username"
            static let passwordKey = "password"
            static let autogeneratedKey = "autogenerated"
        }
        
        let username: String?
        let password: String
        let autogenerated: Bool
        
        init(username: String?, password: String, autogenerated: Bool = false) {
            self.username = username
            self.password = password
            self.autogenerated = autogenerated
        }
        
        init?(autofillDictionary: [String: Any]) {
            guard let credentialsDictionary = autofillDictionary[Constants.credentialsKey] as? [String: Any],
                  let password = credentialsDictionary[Constants.passwordKey] as? String else {
                      return nil
                  }
            
            // Usernames are optional, as the Autofill script can pass a generated password through without a corresponding username.
            self.init(username: credentialsDictionary[Constants.usernameKey] as? String,
                      password: password,
                      autogenerated: (credentialsDictionary[Constants.autogeneratedKey] as? Bool) ?? false)
        }

    }
    
    /// Represents the incoming Autofill data provided by the user script.
    ///
    /// Identities and Credit Cards can be converted to their final model objects directly, but credentials cannot as they have to looked up in the Secure Vault first, hence the existence of a standalone
    /// `IncomingCredentials` type.
    public struct DetectedAutofillData {
        
        public let identity: SecureVaultModels.Identity?
        public let credentials: IncomingCredentials?
        public let creditCard: SecureVaultModels.CreditCard?
        
        var hasAutogeneratedPassword: Bool {
            return credentials?.autogenerated ?? false
        }
        
        init(dictionary: [String: Any]) {
            self.identity = .init(autofillDictionary: dictionary)
            self.creditCard = .init(autofillDictionary: dictionary)
            self.credentials = IncomingCredentials(autofillDictionary: dictionary)
        }
        
        init(identity: SecureVaultModels.Identity?, credentials: AutofillUserScript.IncomingCredentials?, creditCard: SecureVaultModels.CreditCard?) {
            self.identity = identity
            self.credentials = credentials
            self.creditCard = creditCard
        }
        
    }

    // MARK: - Responses

    // swiftlint:disable nesting
    struct RequestAutoFillInitDataResponse: Codable {

        struct AutofillInitSuccess: Codable {
            let serializedInputContext: String?
            let credentials: [CredentialObject]
            let creditCards: [CreditCardObject]
            let identities: [IdentityObject]
        }

        let success: AutofillInitSuccess
        let error: String?

    }

    enum CredentialProviderStatus: String, Codable {
        case locked
        case unlocked
    }

    struct AvailableInputTypesSuccess: Codable {

        struct AvailableInputTypesCredentials: Codable {
            let username: Bool
            let password: Bool
        }

        struct AvailableInputTypesIdentities: Codable {
            let firstName: Bool
            let middleName: Bool
            let lastName: Bool
            let birthdayDay: Bool
            let birthdayMonth: Bool
            let birthdayYear: Bool
            let addressStreet: Bool
            let addressStreet2: Bool
            let addressCity: Bool
            let addressProvince: Bool
            let addressPostalCode: Bool
            let addressCountryCode: Bool
            let phone: Bool
            let emailAddress: Bool
        }

        struct AvailableInputTypesCreditCards: Codable {
            let cardName: Bool
            let cardSecurityCode: Bool
            let expirationMonth: Bool
            let expirationYear: Bool
            let cardNumber: Bool
        }

        let credentials: AvailableInputTypesCredentials
        let identities: AvailableInputTypesIdentities
        let creditCards: AvailableInputTypesCreditCards
        let email: Bool
        let credentialsProviderStatus: CredentialProviderStatus

    }

    struct RequestAvailableInputTypesResponse: Codable {
        let success: AvailableInputTypesSuccess
        let error: String?
    }

    struct RequestAutofillDataResponse: Codable {
        let success: CredentialObject
        let error: String?
    }
    // swiftlint:enable nesting

    struct RequestAutoFillCreditCardResponse: Codable {
        let success: CreditCardObject
        let error: String?
    }

    struct RequestAutoFillIdentityResponse: Codable {

        let success: IdentityObject
        let error: String?

    }

    struct RequestVaultAccountsResponse: Codable {

        let success: [CredentialObject]

    }
    
    struct CredentialResponse: Codable {

        let id: String // When bitwarden is locked use id = "provider_locked"
        let username: String
        let password: String
        let credentialsProvider: String

    }

    struct AskToUnlockProviderResponse: Codable {

        struct AskToUnlockProviderResponseContents: Codable {
            let status: CredentialProviderStatus
            let credentials: [CredentialResponse]
            let availableInputTypes: AvailableInputTypesSuccess
        }

        let success: AskToUnlockProviderResponseContents

    }

    // GetAutofillDataResponse: https://github.com/duckduckgo/duckduckgo-autofill/blob/main/src/deviceApiCalls/schemas/getAutofillData.result.json
    // swiftlint:disable nesting
    struct RequestVaultCredentialsForDomainResponse: Codable {

        struct RequestVaultCredentialsResponseContents: Codable {
            let credentials: CredentialResponse?
            let action: RequestVaultCredentialsAction
        }
        
        let success: RequestVaultCredentialsResponseContents
        
        static func responseFromSecureVaultWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials?,
                                                              credentialsProvider: SecureVaultModels.CredentialsProvider,
                                                              action: RequestVaultCredentialsAction) -> Self {
            let credential: CredentialResponse?
            if let credentials = credentials, let id = credentials.account.id, let password = String(data: credentials.password, encoding: .utf8) {
                credential = CredentialResponse(id: String(id), username: credentials.account.username, password: password, credentialsProvider: credentialsProvider.name.rawValue)
            } else {
                credential = nil
            }
            
            return RequestVaultCredentialsForDomainResponse(success: RequestVaultCredentialsResponseContents(credentials: credential, action: action))
        }
    }
    
    struct RequestVaultCredentialsForAccountResponse: Codable {
        let success: CredentialResponse
    }

    // swiftlint:enable nesting

    // MARK: - Message Handlers

    func getAvailableInputTypes(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        let domain = hostForMessage(message)
        let email = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        vaultDelegate?.autofillUserScript(self, didRequestAutoFillInitDataForDomain: domain) { accounts, identities, cards, credentialsProvider  in
            let response = RequestAvailableInputTypesResponse(accounts: accounts,
                                                              identities: identities,
                                                              cards: cards,
                                                              email: email,
                                                              credentialsProvider: credentialsProvider)
            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }
    }

    // https://github.com/duckduckgo/duckduckgo-autofill/blob/main/src/deviceApiCalls/schemas/getAutofillData.params.json
    struct GetAutofillDataRequest: Codable {
        let mainType: GetAutofillDataMainType
        let subType: GetAutofillDataSubType
        let trigger: GetTriggerType
    }

    // https://github.com/duckduckgo/duckduckgo-autofill/blob/main/src/deviceApiCalls/schemas/getAutofillData.params.json
    public enum GetAutofillDataMainType: String, Codable {
        case credentials
        case identities
        case creditCards
    }

    // https://github.com/duckduckgo/duckduckgo-autofill/blob/main/src/deviceApiCalls/schemas/getAutofillData.params.json
    public enum GetAutofillDataSubType: String, Codable {
        case username
        case password
    }
    
    // https://github.com/duckduckgo/duckduckgo-autofill/blob/main/src/deviceApiCalls/schemas/getAutofillData.params.json
    public enum GetTriggerType: String, Codable {
        case userInitiated
        case autoprompt
    }

    // https://github.com/duckduckgo/duckduckgo-autofill/blob/main/docs/runtime.ios.md#getautofilldatarequest
    func getAutofillData(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let request: GetAutofillDataRequest = DecodableHelper.decode(from: message.messageBody) else {
            return
        }

        let domain = hostForMessage(message)

        vaultDelegate?.autofillUserScript(self,
                                          didRequestCredentialsForDomain: domain,
                                          subType: request.subType,
                                          trigger: request.trigger) { credentials, credentialsProvider, action in
            let response = RequestVaultCredentialsForDomainResponse.responseFromSecureVaultWebsiteCredentials(credentials,
                                                                                                              credentialsProvider: credentialsProvider,
                                                                                                              action: action)

            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }
    }

    func pmGetAutoFillInitData(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        let domain = hostForMessage(message)
        vaultDelegate?.autofillUserScript(self, didRequestAutoFillInitDataForDomain: domain) { accounts, identities, cards, credentialsProvider in
            let credentials: [CredentialObject]
            if credentialsProvider.locked {
                credentials = [CredentialObject(id: "provider_locked", username: "", credentialsProvider: credentialsProvider.name.rawValue)]
            } else {
                credentials = accounts.compactMap {
                    guard let id = $0.id else { return nil }
                    return CredentialObject(id: id, username: $0.username, credentialsProvider: credentialsProvider.name.rawValue)
                }
            }

            let identities: [IdentityObject] = identities.compactMap(IdentityObject.from(identity:))
            let cards: [CreditCardObject] = cards.compactMap(CreditCardObject.autofillInitializationValueFrom(card:))

            let success = RequestAutoFillInitDataResponse.AutofillInitSuccess(serializedInputContext: self.serializedInputContext,
                                                                              credentials: credentials,
                                                                              creditCards: cards,
                                                                              identities: identities)

            let response = RequestAutoFillInitDataResponse(success: success, error: nil)
            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }

    }
     
    func pmStoreData(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        defer {
            replyHandler(nil)
        }
        
        guard let body = message.messageBody as? [String: Any] else {
            return
        }
        
        let incomingData = DetectedAutofillData(dictionary: body)
        let domain = hostProvider.hostForMessage(message)
        
        vaultDelegate?.autofillUserScript(self, didRequestStoreDataForDomain: domain, data: incomingData)
    }

    func pmGetAccounts(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {

        vaultDelegate?.autofillUserScript(self, didRequestAccountsForDomain: hostForMessage(message)) { credentials, credentialsProvider  in
            let credentials: [CredentialObject] = credentials.compactMap {
                guard let id = $0.id else { return nil }
                return .init(id: id, username: $0.username, credentialsProvider: credentialsProvider.name.rawValue)
            }

            let response = RequestVaultAccountsResponse(success: credentials)
            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }

    }

    func pmGetAutofillCredentials(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {

        guard let body = message.messageBody as? [String: Any],
              let id = body["id"] as? String else {
            return
        }
        let requestingDomain = hostForMessage(message)

        vaultDelegate?.autofillUserScript(self, didRequestCredentialsForAccount: id) { credentials, credentialsProvider in
            guard let credential = credentials,
                  let id = credential.account.id,
                  let password = String(data: credential.password, encoding: .utf8),
                  credential.account.domain.droppingWwwPrefix() == requestingDomain.droppingWwwPrefix() else {
                replyHandler("{}")
                return
            }

            let response = RequestVaultCredentialsForAccountResponse(success: .init(id: id,
                                                                                    username: credential.account.username,
                                                                                    password: password,
                                                                                    credentialsProvider: credentialsProvider.name.rawValue))
            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }
    }

    func pmGetCreditCard(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let body = message.messageBody as? [String: Any],
              let id = body["id"] as? String,
              let cardId = Int64(id) else {
            return
        }

        vaultDelegate?.autofillUserScript(self, didRequestCreditCardWithId: Int64(cardId)) {
            guard let card = $0, let cardObject = CreditCardObject.from(card: card) else { return }

            let response = RequestAutoFillCreditCardResponse(success: cardObject, error: nil)

            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }
    }

    func pmGetIdentity(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let body = message.messageBody as? [String: Any],
              let id = body["id"] as? String,
              let accountId = Int64(id) else {
            return
        }

        vaultDelegate?.autofillUserScript(self, didRequestIdentityWithId: Int64(accountId)) {
            guard let identity = $0, let identityObject = IdentityObject.from(identity: identity) else { return }

            let response = RequestAutoFillIdentityResponse(success: identityObject, error: nil)

            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }
    }
    
    func askToUnlockProvider(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        let domain = hostForMessage(message)
        let email = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        vaultDelegate?.autofillUserScriptDidAskToUnlockCredentialsProvider(self,
                                                                           andProvideCredentialsForDomain: domain,
                                                                           completionHandler: { credentials, identities, cards, credentialsProvider in
            let response = AskToUnlockProviderResponse(credentials: credentials,
                                                       identities: identities,
                                                       cards: cards,
                                                       email: email,
                                                       credentialsProvider: credentialsProvider)

            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        })
    }
    
    // On Catalina we poll this method every x seconds from all tabs
    func checkCredentialsProviderStatus(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        if #available(macOS 11, *) {
            return
        }

        let domain = hostForMessage(message)
        let email = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        vaultDelegate?.autofillUserScript(self, didRequestCredentialsForDomain: domain, completionHandler: { credentials, credentialsProvider in
            let response = AskToUnlockProviderResponse(credentials: credentials,
                                                       identities: [],
                                                       cards: [],
                                                       email: email,
                                                       credentialsProvider: credentialsProvider)

            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        })
    }

    // MARK: Open Management Views

    func pmOpenManageCreditCards(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        vaultDelegate?.autofillUserScript(self, didRequestPasswordManagerForDomain: hostForMessage(message))
        replyHandler(nil)
    }

    func pmOpenManageIdentities(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        vaultDelegate?.autofillUserScript(self, didRequestPasswordManagerForDomain: hostForMessage(message))
        replyHandler(nil)
    }

    func pmOpenManagePasswords(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        vaultDelegate?.autofillUserScript(self, didRequestPasswordManagerForDomain: hostForMessage(message))
        replyHandler(nil)
    }

    // MARK: Pixels

    public struct JSPixel: Equatable {

        /// The pixel name sent by the JS layer. This name does not include the platform on which it was sent.
        public let pixelName: String

    }

    func sendJSPixel(_ message: UserScriptMessage, replyHandler: @escaping MessageReplyHandler) {
        defer {
            replyHandler(nil)
        }

        guard let body = message.messageBody as? [String: Any],
              let pixelName = body["pixelName"] as? String else {
            return
        }

        vaultDelegate?.autofillUserScript(self, didSendPixel: JSPixel(pixelName: pixelName))
    }

}

extension AutofillUserScript.RequestAvailableInputTypesResponse {

    init(accounts: [SecureVaultModels.WebsiteAccount],
         identities: [SecureVaultModels.Identity],
         cards: [SecureVaultModels.CreditCard],
         email: Bool,
         credentialsProvider: SecureVaultModels.CredentialsProvider) {
        let credentialObjects: [AutofillUserScript.CredentialObject] = accounts.compactMap {
            guard let id = $0.id else { return nil }
            return .init(id: id, username: $0.username, credentialsProvider: credentialsProvider.name.rawValue)
        }
        let username = credentialsProvider.locked || credentialObjects.filter({ !$0.username.isEmpty }).count > 0
        let password = credentialsProvider.locked || credentialObjects.count > 0
        let identities = AutofillUserScript.AvailableInputTypesSuccess.AvailableInputTypesIdentities(identities: identities)
        let cards = AutofillUserScript.AvailableInputTypesSuccess.AvailableInputTypesCreditCards(creditCards: cards)
        let credentials = AutofillUserScript.AvailableInputTypesSuccess.AvailableInputTypesCredentials(username: username, password: password)
        let success = AutofillUserScript.AvailableInputTypesSuccess(
            credentials: credentials,
            identities: identities,
            creditCards: cards,
            email: email,
            credentialsProviderStatus: credentialsProvider.locked ? .locked : .unlocked
        )
        self.init(success: success, error: nil)
    }

    init(credentials: [SecureVaultModels.WebsiteCredentials],
         identities: [SecureVaultModels.Identity],
         cards: [SecureVaultModels.CreditCard],
         email: Bool,
         credentialsProvider: SecureVaultModels.CredentialsProvider) {
        let username = credentialsProvider.locked || credentials.filter({ !$0.account.username.isEmpty }).count > 0
        let password = credentialsProvider.locked || credentials.count > 0
        let credentials = AutofillUserScript.AvailableInputTypesSuccess.AvailableInputTypesCredentials(username: username, password: password)
        let success = AutofillUserScript.AvailableInputTypesSuccess(
            credentials: credentials,
            identities: AutofillUserScript.AvailableInputTypesSuccess.AvailableInputTypesIdentities(identities: identities),
            creditCards: AutofillUserScript.AvailableInputTypesSuccess.AvailableInputTypesCreditCards(creditCards: cards),
            email: email,
            credentialsProviderStatus: credentialsProvider.locked ? .locked : .unlocked
        )
        self.init(success: success, error: nil)
    }

}

extension AutofillUserScript.AvailableInputTypesSuccess.AvailableInputTypesIdentities {

    init(identities: [SecureVaultModels.Identity]) {

        var (firstName, middleName, lastName, birthdayDay, birthdayMonth, birthdayYear,
            addressStreet, addressStreet2, addressCity, addressProvince, addressPostalCode,
            addressCountryCode, phone, emailAddress) =
        (false, false, false, false, false, false, false, false, false, false, false, false, false, false)

        for identity in identities {
            firstName = firstName || !(identity.firstName ?? "").isEmpty
            middleName = middleName || !(identity.middleName ?? "").isEmpty
            lastName = lastName || !(identity.lastName ?? "").isEmpty
            birthdayDay = birthdayDay || identity.birthdayDay != nil
            birthdayMonth = birthdayMonth || identity.birthdayMonth != nil
            birthdayYear = birthdayYear || identity.birthdayYear != nil
            addressStreet = addressStreet || !(identity.addressStreet ?? "").isEmpty
            addressStreet2 = addressStreet2 || !(identity.addressStreet2 ?? "").isEmpty
            addressCity = addressCity || !(identity.addressCity ?? "").isEmpty
            addressProvince = addressProvince || !(identity.addressProvince ?? "").isEmpty
            addressPostalCode = addressPostalCode || !(identity.addressPostalCode ?? "").isEmpty
            addressCountryCode = addressCountryCode || !(identity.addressCountryCode ?? "").isEmpty
            phone = phone || !(identity.homePhone ?? "").isEmpty || !(identity.mobilePhone ?? "").isEmpty
            emailAddress = emailAddress || !(identity.emailAddress ?? "").isEmpty
        }

        self.init(firstName: firstName,
                  middleName: middleName,
                  lastName: lastName,
                  birthdayDay: birthdayDay,
                  birthdayMonth: birthdayMonth,
                  birthdayYear: birthdayYear,
                  addressStreet: addressStreet,
                  addressStreet2: addressStreet2,
                  addressCity: addressCity,
                  addressProvince: addressProvince,
                  addressPostalCode: addressPostalCode,
                  addressCountryCode: addressCountryCode,
                  phone: phone,
                  emailAddress: emailAddress)
    }

}

extension AutofillUserScript.AvailableInputTypesSuccess.AvailableInputTypesCreditCards {

    init(creditCards: [SecureVaultModels.CreditCard]) {
        var (cardName, cardSecurityCode, expirationMonth, expirationYear, cardNumber) =
        (false, false, false, false, false)

        for card in creditCards {
            cardName = cardName || !(card.cardholderName ?? "").isEmpty
            cardSecurityCode = cardSecurityCode || !(card.cardSecurityCode ?? "").isEmpty
            expirationMonth = expirationMonth || card.expirationMonth != nil
            expirationYear = expirationYear || card.expirationYear != nil
            cardNumber = true
        }

        self.init(cardName: cardName,
                  cardSecurityCode: cardSecurityCode,
                  expirationMonth: expirationMonth,
                  expirationYear: expirationYear,
                  cardNumber: cardNumber)
    }
}

extension AutofillUserScript.AskToUnlockProviderResponse {

    init(credentials: [SecureVaultModels.WebsiteCredentials],
         identities: [SecureVaultModels.Identity],
         cards: [SecureVaultModels.CreditCard],
         email: Bool,
         credentialsProvider: SecureVaultModels.CredentialsProvider) {

        let availableInputTypesResponse = AutofillUserScript.RequestAvailableInputTypesResponse(credentials: credentials,
                                                                             identities: identities,
                                                                             cards: cards,
                                                                             email: email,
                                                                             credentialsProvider: credentialsProvider)
        let status = credentialsProvider.locked ? AutofillUserScript.CredentialProviderStatus.locked : .unlocked
        let credentialsArray:[AutofillUserScript.CredentialResponse] = credentials.compactMap { credential in
            guard let id = credential.account.id else {
                return nil
            }

            return AutofillUserScript.CredentialResponse(id: String(id),
                                                         username: credential.account.username,
                                                         password: String(data: credential.password, encoding:.utf8) ?? "",
                                                         credentialsProvider: credentialsProvider.name.rawValue)
        }

        let availableInputTypes = availableInputTypesResponse.success
        let success = AutofillUserScript.AskToUnlockProviderResponse.AskToUnlockProviderResponseContents(status: status, credentials: credentialsArray, availableInputTypes: availableInputTypes)
        self.init(success: success)
    }

}

// swiftlint:enable file_length
