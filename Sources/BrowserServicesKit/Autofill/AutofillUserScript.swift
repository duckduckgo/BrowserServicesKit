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

public protocol AutofillUserScriptDelegate: AnyObject {

    func clickTriggered(clickPoint: NSPoint)

}

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
    var view: NSView { get }
    func getContentOverlayPopover(_ response: AutofillMessaging) -> ContentOverlayPopover?
}


public class AutofillUserScript: NSObject, UserScript, AutofillMessaging {

    typealias MessageReplyHandler = (String?) -> Void
    typealias MessageHandler = (WKScriptMessage, @escaping MessageReplyHandler) -> Void

    public var lastOpenHost: String?

    private enum MessageName: String, CaseIterable {
        case getSelectedCredentials
        case showAutofillParent
        case closeAutofillParent
        case emailHandlerStoreToken

        case emailHandlerGetAddresses
        case emailHandlerCheckAppSignedInStatus

        case pmHandlerGetAutofillInitData
    }

    public var topView: OverlayProtocol?
    public var clickPoint: NSPoint?

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
        print("TODOJKT got message \(message) \(self) \(#function) ")
        switch message {
        case .getSelectedCredentials: return getSelectedCredentials
        case .showAutofillParent: return showAutofillParent
        case .closeAutofillParent: return closeAutofillParent
        case .emailHandlerStoreToken: return emailStoreToken
        case .emailHandlerGetAddresses: return emailGetAddresses
        case .emailHandlerCheckAppSignedInStatus: return emailCheckSignedInStatus

        case .pmHandlerGetAutofillInitData: return pmGetAutoFillInitData
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
    
    public func messageSelectedCredential(_ data: [String: String], _ configType: String) {
        print("TODOJKT messsaged to af! \(data) \(lastOpenHost) \(self) \(#function) ")
        guard let topView = topView else { return }
        topView.getContentOverlayPopover(self)?.close()
        selectedCredential = data
        selectedConfigType = configType
    }
    
    public func close() {
        guard let topView = topView else { return }
        topView.getContentOverlayPopover(self)?.close()
        // TODO cleanup injected script
    }
    
    var selectedCredential: [String: String]?
    var selectedConfigType: String?
    
    func closeAutofillParent(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let topView = topView else { return }
        let popover = topView.getContentOverlayPopover(self)!;
        selectedCredential = nil
        selectedConfigType = nil
        lastOpenHost = nil
        popover.close()
        replyHandler(nil)
    }
    
    func showAutofillParent(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        print("TODOJKT showAutofillParent \(self) \(#function) \(topView) \(clickPoint)")
        guard let dict = message.body as? [String: Any],
              let left = dict["inputLeft"] as? CGFloat,
              let top = dict["inputTop"] as? CGFloat,
              let height = dict["inputHeight"] as? CGFloat,
              var width = dict["inputWidth"] as? CGFloat,
              let inputType = dict["inputType"] as? String,
              let topView = topView,
              let clickPoint = clickPoint else {
                  return
              }
        print("TODOJKT showAutofillParent \(inputType)")
        // Sets the last message host, so we can check when it messages back
        lastOpenHost = hostProvider.hostForMessage(message)
        
        let popover = topView.getContentOverlayPopover(self)!;
        let zf = popover.zoomFactor!
        // Combines native click with offset of dax click.
        let clickX = CGFloat(clickPoint.x);
        let clickY = CGFloat(clickPoint.y);
        let y = (clickY - (height - top)) * zf;
        let x = (clickX - left) * zf;
        print("TODOJKT calc click x \(clickX) click y \(clickY) top: \(top) y: \(y) x: \(x) zf: \(zf)")
        var rectWidth = width * zf
        // If the field is wider we want to left assign the rectangle anchoring
        if (width > 315) {
            rectWidth = 315 * zf
        }
        let rect = NSRect(x: x, y: y, width: rectWidth, height: height * zf)
        // Convert to webview coordinate system
        print("TODOJKT pos: \(rect) -- \(top) \(height) -- click: \(clickPoint)")
        // TODO make 315 a constant
        if (width < 315) {
            width = 315
        }
        popover.display(rect: rect, of: topView.view, width: width, inputType: inputType)
        replyHandler(nil)
    }
    
    struct getSelectedCredentialsResponse: Encodable {
        var type: String
        var data: [String: String]?
        var configType: String?
    }
    
    func getSelectedCredentials(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        var response = getSelectedCredentialsResponse(type: "none")
        if (lastOpenHost == nil || message.frameInfo.securityOrigin.host != lastOpenHost!) {
            response = getSelectedCredentialsResponse(type: "stop")
        } else if (selectedCredential != nil) {
            response = getSelectedCredentialsResponse(type: "ok", data: selectedCredential!, configType: selectedConfigType)
        }
        if let json = try? JSONEncoder().encode(response),
           let jsonString = String(data: json, encoding: .utf8) {
            replyHandler(jsonString)
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
