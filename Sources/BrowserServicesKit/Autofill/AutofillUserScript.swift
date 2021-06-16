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

public protocol AutofillEmailDelegate: AnyObject {

    func autofillUserScript(_: AutofillUserScript,
                            didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                            shouldConsumeAliasIfProvided: Bool,
                            completionHandler: @escaping AliasCompletion)
    func autofillUserScriptDidRequestRefreshAlias(_ : AutofillUserScript)
    func autofillUserScript(_: AutofillUserScript, didRequestStoreToken token: String, username: String)
    func autofillUserScriptDidRequestUsernameAndAlias(_ : AutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion)
    func autofillUserScriptDidRequestSignedInStatus(_: AutofillUserScript) -> Bool

}

public protocol AutofillSecureVaultDelegate: AnyObject {

    func autofillUserScript(_: AutofillUserScript, didRequestPasswordManagerForDomain domain: String)
    func autofillUserScript(_: AutofillUserScript, didRequestStoreCredentials username: String, password: String)

}

public class AutofillUserScript: NSObject, UserScript {

    typealias MessageReplyHandler = (String?) -> Void
    typealias MessageHandler = (WKScriptMessage, @escaping MessageReplyHandler) -> Void

    private enum MessageName: String, CaseIterable {
        case emailHandlerStoreToken
        case emailHandlerGetAlias
        case emailHandlerRefreshAlias
        case emailHandlerGetAddresses
        case emailHandlerCheckAppSignedInStatus
        case pmHandlerStoreCredentials
        case pmHandlerGetCredentials
        case pmHandlerGetAutofillCredentials
        case pmHandlerOpenManagePasswords
    }

    public weak var emailDelegate: AutofillEmailDelegate?
    public weak var vaultDelegate: AutofillSecureVaultDelegate?

    public lazy var source: String = {
        var replacements: [String: String] = [:]
        #if os(macOS)
            replacements["// INJECT isApp HERE"] = "isApp = true;"
        #endif

        if #available(iOS 14, macOS 11, *) {
            replacements["// INJECT hasModernWebkitAPI HERE"] = "hasModernWebkitAPI = true;"
        } else {
            replacements["PLACEHOLDER_SECRET"] = generatedSecret
        }

        return AutofillUserScript.loadJS("autofill", from: Bundle.module, withReplacements: replacements)
    }()

    public var injectionTime: WKUserScriptInjectionTime { .atDocumentStart }
    public var forMainFrameOnly: Bool { false }
    public var messageNames: [String] { MessageName.allCases.map(\.rawValue) }

    private func messageHandlerFor(_ message: MessageName) -> MessageHandler {
        switch message {
        case .emailHandlerStoreToken: return emailStoreToken
        case .emailHandlerGetAlias: return emailGetAlias
        case .emailHandlerRefreshAlias: return emailRefreshAlias
        case .emailHandlerGetAddresses: return emailGetAddresses
        case .emailHandlerCheckAppSignedInStatus: return emailCheckSignedInStatus
        case .pmHandlerStoreCredentials: return pmStoreCredentials
        case .pmHandlerGetCredentials: return pmGetCredentials
        case .pmHandlerGetAutofillCredentials: return pmGetAutofillCredentials
        case .pmHandlerOpenManagePasswords: return pmOpenManagePasswords
        }
    }

    private let encrypter: AutofillEncrypter

    let generatedSecret: String = UUID().uuidString

    public init(encrypter: AutofillEncrypter = AESGCMAutofillEncrypter()) {
        self.encrypter = encrypter
    }

    private func pmStoreCredentials(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        defer {
            replyHandler(nil)
        }

        guard let body = message.body as? [String: Any],
              let username = body["username"] as? String,
              let password = body["password"] as? String else {
            return
        }

        vaultDelegate?.autofillUserScript(self, didRequestStoreCredentials: username, password: password)
    }

    private func pmGetCredentials(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        replyHandler("""
        {
            \"success\": [{
                \"id\": 123,
                \"username\": \"user@name.com\",
                \"lastUpdated\": 1623221677121
            }]
        }
        """)
//        replyHandler("""
//        {
//            \"success\": []
//        }
//        """)
    }
    
    private func pmGetAutofillCredentials(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        replyHandler("""
        {
            \"success\": {
                \"id\": 123,
                \"username\": \"user@name.com\",
                \"password\": \"abcd1234!\",
                \"lastUpdated\": 1623221677121
            }
        }
        """)
//        replyHandler("""
//        {
//            \"success\": { }
//        }
//        """)
    }
    
    private func pmOpenManagePasswords(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        vaultDelegate?.autofillUserScript(self, didRequestPasswordManagerForDomain: message.frameInfo.securityOrigin.host)
        replyHandler(nil)
    }

    private func emailCheckSignedInStatus(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        let signedIn = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        let signedInString = String(signedIn)
        replyHandler("""
            { "isAppSignedIn": \(signedInString) }
        """)
    }

    private func emailStoreToken(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let token = dict["token"] as? String,
              let username = dict["username"] as? String else { return }
        emailDelegate?.autofillUserScript(self, didRequestStoreToken: token, username: username)
        replyHandler(nil)
    }

    private func emailGetAlias(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let requiresUserPermission = dict["requiresUserPermission"] as? Bool,
              let shouldConsumeAliasIfProvided = dict["shouldConsumeAliasIfProvided"] as? Bool else { return }

        emailDelegate?.autofillUserScript(self,
                                  didRequestAliasAndRequiresUserPermission: requiresUserPermission,
                                  shouldConsumeAliasIfProvided: shouldConsumeAliasIfProvided) { alias, _ in
            guard let alias = alias else { return }

            replyHandler("""
            {
                "alias": "\(alias)"
            }
            """)
        }
    }

    private func emailRefreshAlias(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestRefreshAlias(self)
        replyHandler(nil)
    }

    private func emailGetAddresses(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
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
              secret == generatedSecret else { return }

        messageHandlerFor(messageName)(message) { reply in
            guard let reply = reply,
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
                window.\(methodName)({
                    ciphertext: [\(ciphertext)],
                    tag: [\(tag)]
                });
            })()
            """

            assert(message.webView != nil)
            dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
            message.webView?.evaluateJavaScript(script)
        }
    }

}
