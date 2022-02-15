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

public protocol TopAutofillSecureVaultDelegate: AnyObject {

    func topAutofillUserScript(_: TopAutofillUserScript, didRequestAutoFillInitDataForDomain domain: String, completionHandler: @escaping (
        [SecureVaultModels.WebsiteAccount],
        [SecureVaultModels.Identity],
        [SecureVaultModels.CreditCard]
    ) -> Void)

    func topAutofillUserScript(_: TopAutofillUserScript, didRequestPasswordManagerForDomain domain: String)
    func topAutofillUserScript(_: TopAutofillUserScript, didRequestStoreCredentialsForDomain domain: String, username: String, password: String)
    func topAutofillUserScript(_: TopAutofillUserScript, didRequestAccountsForDomain domain: String,
                            completionHandler: @escaping ([SecureVaultModels.WebsiteAccount]) -> Void)
    func topAutofillUserScript(_: TopAutofillUserScript, didRequestCredentialsForAccount accountId: Int64,
                            completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?) -> Void)
    func topAutofillUserScript(_: TopAutofillUserScript, didRequestCreditCardWithId creditCardId: Int64,
                            completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void)
    func topAutofillUserScript(_: TopAutofillUserScript, didRequestIdentityWithId identityId: Int64,
                            completionHandler: @escaping (SecureVaultModels.Identity?) -> Void)

}

extension TopAutofillUserScript {

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
                                  emailAddress: identity.emailAddress)
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
        let id: Int64
        let username: String
    }

    // MARK: - Responses

    // swiftlint:disable nesting
    struct RequestAutoFillInitDataResponse: Codable {

        struct AutofillInitSuccess: Codable {
            let credentials: [CredentialObject]
            let creditCards: [CreditCardObject]
            let identities: [IdentityObject]
        }

        let success: AutofillInitSuccess
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

    // swiftlint:disable nesting
    struct RequestVaultCredentialsResponse: Codable {

        struct Credential: Codable {
            let id: Int64
            let username: String
            let password: String
            let lastUpdated: TimeInterval
        }

        let success: Credential

    }
    // swiftlint:enable nesting

    // MARK: - Message Handlers

    func pmGetAutoFillInitData(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        let domain = hostForMessage()
        vaultDelegate?.topAutofillUserScript(self, didRequestAutoFillInitDataForDomain: domain) { accounts, identities, cards in
            let credentials: [CredentialObject] = accounts.compactMap {
                guard let id = $0.id else { return nil }
                return .init(id: id, username: $0.username)
            }

            let identities: [IdentityObject] = identities.compactMap(IdentityObject.from(identity:))
            let cards: [CreditCardObject] = cards.compactMap(CreditCardObject.autofillInitializationValueFrom(card:))

            let success = RequestAutoFillInitDataResponse.AutofillInitSuccess(credentials: credentials,
                                                                              creditCards: cards,
                                                                              identities: identities)

            let response = RequestAutoFillInitDataResponse(success: success, error: nil)
            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }

    }

    func pmStoreCredentials(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        defer {
            replyHandler(nil)
        }

        guard let body = message.body as? [String: Any],
              let username = body["username"] as? String,
              let password = body["password"] as? String else {
            return
        }

        let domain = hostForMessage()
        vaultDelegate?.topAutofillUserScript(self, didRequestStoreCredentialsForDomain: domain, username: username, password: password)
    }

    func pmGetAccounts(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {

        vaultDelegate?.topAutofillUserScript(self, didRequestAccountsForDomain: hostForMessage()) { credentials in
            let credentials: [CredentialObject] = credentials.compactMap {
                guard let id = $0.id else { return nil }
                return .init(id: id, username: $0.username)
            }

            let response = RequestVaultAccountsResponse(success: credentials)
            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }

    }

    func pmGetAutofillCredentials(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {

        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let accountId = Int64(id) else {
            return
        }

        vaultDelegate?.topAutofillUserScript(self, didRequestCredentialsForAccount: Int64(accountId)) {
            guard let credential = $0,
                  let id = credential.account.id,
                  let password = String(data: credential.password, encoding: .utf8) else { return }

            let response = RequestVaultCredentialsResponse(success: .init(id: id,
                                                                     username: credential.account.username,
                                                                     password: password,
                                                                     lastUpdated: credential.account.lastUpdated.timeIntervalSince1970))
            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }
    }

    func pmGetCreditCard(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let cardId = Int64(id) else {
            return
        }

        vaultDelegate?.topAutofillUserScript(self, didRequestCreditCardWithId: Int64(cardId)) {
            guard let card = $0, let cardObject = CreditCardObject.from(card: card) else { return }

            let response = RequestAutoFillCreditCardResponse(success: cardObject, error: nil)

            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }
    }

    func pmGetIdentity(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let accountId = Int64(id) else {
            return
        }

        vaultDelegate?.topAutofillUserScript(self, didRequestIdentityWithId: Int64(accountId)) {
            guard let identity = $0, let identityObject = IdentityObject.from(identity: identity) else { return }

            let response = RequestAutoFillIdentityResponse(success: identityObject, error: nil)

            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }
    }

    // MARK: Open Management Views

    func pmOpenManageCreditCards(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        vaultDelegate?.topAutofillUserScript(self, didRequestPasswordManagerForDomain: hostForMessage())
        replyHandler(nil)
    }

    func pmOpenManageIdentities(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        vaultDelegate?.topAutofillUserScript(self, didRequestPasswordManagerForDomain: hostForMessage())
        replyHandler(nil)
    }

    func pmOpenManagePasswords(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        vaultDelegate?.topAutofillUserScript(self, didRequestPasswordManagerForDomain: hostForMessage())
        replyHandler(nil)
    }

}
