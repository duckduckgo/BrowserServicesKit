//
//  AutofillUserScript.swift
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
// import SwiftUI

public protocol AutofillEmailDelegate: AnyObject {

    func autofillUserScript(_: AutofillUserScript,
                            didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                            shouldConsumeAliasIfProvided: Bool,
                            completionHandler: @escaping AliasCompletion)
    func autofillUserScriptDidRequestRefreshAlias(_ : AutofillUserScript)
    func autofillUserScript(_: AutofillUserScript, didRequestStoreToken token: String, username: String, cohort: String?)
    func autofillUserScriptDidRequestUsernameAndAlias(_ : AutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion)
    func autofillUserScriptDidRequestSignedInStatus(_: AutofillUserScript) -> Bool

}

public protocol AutofillSecureVaultDelegate: AnyObject {

    func autofillUserScript(_: AutofillUserScript, didRequestAutoFillInitDataForDomain domain: String, completionHandler: @escaping (
        [SecureVaultModels.WebsiteAccount],
        [SecureVaultModels.Identity],
        [SecureVaultModels.CreditCard]
    ) -> Void)

    // func autofillUserScript(_: AutofillUserScript, didRequestPasswordManagerForDomain domain: String)
    func autofillUserScript(_: AutofillUserScript, didRequestStoreCredentialsForDomain domain: String, username: String, password: String)
    func autofillUserScript(_: AutofillUserScript, didRequestAccountsForDomain domain: String,
                            completionHandler: @escaping ([SecureVaultModels.WebsiteAccount]) -> Void)
    func autofillUserScript(_: AutofillUserScript, didRequestCredentialsForAccount accountId: Int64,
                            completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?) -> Void)
    func autofillUserScript(_: AutofillUserScript, didRequestCreditCardWithId creditCardId: Int64,
                            completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void)
    func autofillUserScript(_: AutofillUserScript, didRequestIdentityWithId identityId: Int64,
                            completionHandler: @escaping (SecureVaultModels.Identity?) -> Void)

}

public protocol OverlayProtocol {
    func getContentOverlayPopover(_ response: AutofillMessaging) -> ContentOverlayPopover?
    var view: NSView { get }
}

/*
protocol AutofillHostProvider {

    func hostForMessage(_ message: WKScriptMessage) -> String

}

struct SecurityOriginHostProvider: AutofillHostProvider {

    public func hostForMessage(_ message: WKScriptMessage) -> String {
        return message.frameInfo.securityOrigin.host
    }

}*/


public class AutofillUserScript: NSObject, UserScript, AutofillMessaging {

    typealias MessageReplyHandler = (String?) -> Void
    typealias MessageHandler = (WKScriptMessage, @escaping MessageReplyHandler) -> Void

    public var lastOpenHost: String?

    private enum MessageName: String, CaseIterable {
        case showAutofillParent
        case closeAutofillParent
        case emailHandlerStoreToken
/*
        case emailHandlerGetAlias
        case emailHandlerRefreshAlias
 */
        case emailHandlerGetAddresses
        case emailHandlerCheckAppSignedInStatus

        case pmHandlerGetAutofillInitData
/*
        case pmHandlerStoreCredentials
        case pmHandlerGetAccounts
        case pmHandlerGetAutofillCredentials
        case pmHandlerGetIdentity
        case pmHandlerGetCreditCard

        case pmHandlerOpenManageCreditCards
        case pmHandlerOpenManageIdentities
        case pmHandlerOpenManagePasswords
 */
    }

    public var topView: OverlayProtocol?

    public weak var emailDelegate: AutofillEmailDelegate?
    public weak var vaultDelegate: AutofillSecureVaultDelegate?

    public lazy var source: String = {
        var replacements: [String: String] = [:]
        #if os(macOS)
            replacements["// INJECT isApp HERE"] = "isApp = true;"
            replacements["// INJECT isTopFrame HERE"] = "isTopFrame = false;"
        #endif

        if #available(iOS 14, macOS 11, *) {
            replacements["// INJECT hasModernWebkitAPI HERE"] = "hasModernWebkitAPI = true;"
        } else {
            replacements["PLACEHOLDER_SECRET"] = generatedSecret
        }

        return AutofillUserScript.loadJS("autofill", from: Bundle.module, withReplacements: replacements)
    }()

    public var injectionTime: WKUserScriptInjectionTime { .atDocumentStart }
    public var forMainFrameOnly: Bool {
        if #available(iOS 14, macOS 11, *) {
            return false
        }
        // We can't do reply based messaging to frames on versions before the ones mentioned above, so main frame only
        return true
    }
    public var requiresRunInPageContentWorld: Bool = true
    public var messageNames: [String] { MessageName.allCases.map(\.rawValue) }

    private func messageHandlerFor(_ message: MessageName) -> MessageHandler {
        print("got message \(message)")
        switch message {
            
        case .showAutofillParent: return showAutofillParent
        case .closeAutofillParent: return closeAutofillParent
        case .emailHandlerStoreToken: return emailStoreToken
/*
        case .emailHandlerGetAlias: return emailGetAlias
        case .emailHandlerRefreshAlias: return emailRefreshAlias
 */
        case .emailHandlerGetAddresses: return emailGetAddresses
        case .emailHandlerCheckAppSignedInStatus: return emailCheckSignedInStatus

        case .pmHandlerGetAutofillInitData: return pmGetAutoFillInitData
/*
        case .pmHandlerStoreCredentials: return pmStoreCredentials
        case .pmHandlerGetAccounts: return pmGetAccounts
        case .pmHandlerGetAutofillCredentials: return pmGetAutofillCredentials

        case .pmHandlerGetIdentity: return pmGetIdentity
        case .pmHandlerGetCreditCard: return pmGetCreditCard

        case .pmHandlerOpenManageCreditCards: return pmOpenManageCreditCards
        case .pmHandlerOpenManageIdentities: return pmOpenManageIdentities
        case .pmHandlerOpenManagePasswords: return pmOpenManagePasswords
 */
        }
    }
    
    func emailStoreToken(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let token = dict["token"] as? String,
              let username = dict["username"] as? String else { return }
        let cohort = dict["cohort"] as? String
        emailDelegate?.autofillUserScript(self, didRequestStoreToken: token, username: username, cohort: cohort)
        replyHandler(nil)
    }
    
    func pmGetAutoFillInitData(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        let domain = hostProvider.hostForMessage(message)
        vaultDelegate?.autofillUserScript(self, didRequestAutoFillInitDataForDomain: domain) { accounts, identities, cards in
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
    
    func emailCheckSignedInStatus(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        let signedIn = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        let signedInString = String(signedIn)
        replyHandler("""
            { "isAppSignedIn": \(signedInString) }
        """)
    }
    
    func emailGetAddresses(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestUsernameAndAlias(self) { username, alias, _ in
            let addresses: String
            if let username = username, let alias = alias {
                addresses = """
                {
                    "personalAddress": "\(username)",
                    "privateAddress": "\(alias)"
                }
                """
            } else {
                addresses = "null"
            }

            replyHandler("""
            {
                "addresses": \(addresses)
            }
            """)
        }
    }
    
    public func messageSelectedCredential<T: Encodable>(_ data: [String: T], _ configType: String) {
        print("messsaged to af! \(data)")
        guard let topView = topView else { return }
        topView.getContentOverlayPopover(self)?.close()
        guard let currentWebView = currentWebView else { return }
        if let json = try? JSONEncoder().encode(data), let jsonString = String(data: json, encoding: .utf8) {
            let script = """
            (() => {
                const event = new CustomEvent("InboundCredential", {
                    detail: {
                        data: \(jsonString),
                        configType: "\(configType)"
                    }
                });
                document.dispatchEvent(event);
            })()
            """
            currentWebView.evaluateJavaScript(script)
        }
    }
    
    weak var currentWebView: WKWebView?
    
    func closeAutofillParent(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let topView = topView else { return }
        let popover = topView.getContentOverlayPopover(self)!;
        currentWebView = nil
        popover.close()
        replyHandler(nil)
    }
    
    func showAutofillParent(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let left = dict["inputLeft"] as? Int,
              let top = dict["inputTop"] as? Int,
              let height = dict["inputHeight"] as? Int,
              let width = dict["inputWidth"] as? Int,
              let inputType = dict["inputType"] as? String,
              let topView = topView else { return }

        lastOpenHost = hostProvider.hostForMessage(message)
        print("show autofill parent x: \(left), y: \(top)- \(dict)")
        
        let popover = topView.getContentOverlayPopover(self)!;
        popover.setTypes(inputType: inputType)
        
        print("zoom: \(popover.zoomFactor) it: \(inputType)")
        let zf = popover.zoomFactor!

        let rect = NSRect(x: left, y: top, width: width, height: height)
        // Convert to webview coordinate system
        let outRect = topView.view.convert(rect, to: popover.webView)
        /* Debug rect placement
        let view = NSView(frame: rect)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.blue.cgColor
        topView.view.addSubview(view)
         */
        print("\(rect) ... \(outRect)")
        
        // Inset the rectangle by the anchor size as setting the anchorSize to 0 seems impossible
        if let insetBy = popover.value(forKeyPath: "anchorSize")! as? CGSize {
            currentWebView = message.webView
            popover.show(relativeTo: rect.insetBy(dx: insetBy.width, dy: insetBy.height), of: popover.webView!, preferredEdge: .maxY)
            popover.contentSize = NSSize.init(width: width, height: 200)
            replyHandler(nil)
        }
    }

    let encrypter: AutofillEncrypter
    let hostProvider: AutofillHostProvider
    let generatedSecret: String = UUID().uuidString

    init(encrypter: AutofillEncrypter, hostProvider: AutofillHostProvider) {
        self.encrypter = encrypter
        self.hostProvider = hostProvider
    }

    public convenience override init() {
        self.init(encrypter: AESGCMAutofillEncrypter(), hostProvider: SecurityOriginHostProvider())
    }

}

@available(iOS 14, *)
@available(macOS 11, *)
extension AutofillUserScript: WKScriptMessageHandlerWithReply {

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage,
                                      replyHandler: @escaping (Any?, String?) -> Void) {
        guard let messageName = MessageName(rawValue: message.name) else { return }

        messageHandlerFor(messageName)(message) {
            replyHandler($0, nil)
        }

    }

}

// Fallback for older iOS / macOS version
extension AutofillUserScript {

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {

        guard let messageName = MessageName(rawValue: message.name),
              let body = message.body as? [String: Any],
              let messageHandling = body["messageHandling"] as? [String: Any],
              let secret = messageHandling["secret"] as? String,
              // If this does not match the page is playing shenanigans.
              secret == generatedSecret
        else { return }

        messageHandlerFor(messageName)(message) { reply in
            guard let reply = reply,
                  let messageHandling = body["messageHandling"] as? [String: Any],
                  let key = messageHandling["key"] as? [UInt8],
                  let iv = messageHandling["iv"] as? [UInt8],
                  let methodName = messageHandling["methodName"] as? String,
                  let encryption = try? self.encrypter.encryptReply(reply, key: key, iv: iv) else { return }

            let ciphertext = encryption.ciphertext.withUnsafeBytes { bytes in
                return bytes.map { String($0) }
            }.joined(separator: ",")

            let tag = encryption.tag.withUnsafeBytes { bytes in
                return bytes.map { String($0) }
            }.joined(separator: ",")

            let script = """
            (() => {
                window.\(methodName) && window.\(methodName)({
                    ciphertext: [\(ciphertext)],
                    tag: [\(tag)]
                });
            })();
            """

            assert(message.webView != nil)
            dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
            message.webView?.evaluateJavaScript(script)
        }
    }

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
                                  lastName: identity.middleName,
                                  birthdayDay: identity.birthdayDay,
                                  birthdayMonth: identity.birthdayMonth,
                                  birthdayYear: identity.birthdayYear,
                                  addressStreet: identity.addressStreet,
                                  addressStreet2: nil,
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
}
