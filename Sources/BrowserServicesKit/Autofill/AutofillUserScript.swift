//
//  EmailUserScript.swift
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

public class AutofillUserScript: NSObject, UserScript {

    typealias MessageReplyHandler = (String) -> Void
    typealias MessageHandler = (WKScriptMessage, @escaping MessageReplyHandler) -> Void

    public weak var emailDelegate: AutofillEmailDelegate?

    public lazy var source: String = {
        #if os(OSX)
            let replacements = ["// INJECT isApp HERE": "isApp = true;"]
        #else
            let replacements: [String: String] = [:]
        #endif
        return AutofillUserScript.loadJS("autofill", from: Bundle.module, withReplacements: replacements)
    }()
    public var injectionTime: WKUserScriptInjectionTime { .atDocumentEnd }
    public var forMainFrameOnly: Bool { false }
    public var messageNames: [String] { messages.keys.map { $0 } }

    private lazy var messages: [String: MessageHandler] = { [
        "emailHandlerStoreToken": emailStoreToken,
        "emailHandlerGetAlias": emailGetAlias,
        "emailHandlerRefreshAlias": emailRefreshAlias,
        "emailHandlerGetAddresses": emailGetAddresses,
        "emailHandlerCheckAppSignedInStatus": emailCheckSignedInStatus
    ] }()

    private func emailCheckSignedInStatus(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        let signedIn = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        let signedInString = String(signedIn)
        replyHandler("isAppSignedIn: \(signedInString)")
    }

    private func emailStoreToken(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let token = dict["token"] as? String,
              let username = dict["username"] as? String else { return }
        emailDelegate?.autofillUserScript(self, didRequestStoreToken: token, username: username)
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
                alias: "\(alias)"
            }
            """)
        }
    }

    private func emailRefreshAlias(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestRefreshAlias(self)
    }

    private func emailGetAddresses(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestUsernameAndAlias(self) { username, alias, _ in
            let addresses: String
            if let username = username, let alias = alias {
                addresses = """
                    personalAddress: "\(username)",
                    privateAddress: "\(alias)"
                """
            } else {
                addresses = "null"
            }

            replyHandler("""
            {
                addresses: \(addresses)
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

        messages[message.name]?(message) {
            replyHandler($0, nil)
        }

    }

}

// Fallback for older iOS / macOS version
extension AutofillUserScript {

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {

        guard let body = message.body as? [String: Any],
              let key = body["key"] as? [Int],
              let iv = body["iv"] as? [Int],
              let methodName = body["methodName"] as? String else { return }

        messages[message.name]?(message) { reply in

            let keyAsString = key.map { "\($0)" }.joined(separator: ",")
            let ivAsString = iv.map { "\($0)" }.joined(separator: ",")

            let script = """
            (() => {
                const messageHandling = PASS THE VARIABLE HERE
                const message = \(reply)

                const ddgGlobals = window.navigator.ddgGlobals

                const iv = new ddgGlobals.Uint8Array(messageHandling.iv)
                const keyBuffer = new ddgGlobals.Uint8Array(messageHandling.key)
                const key = await ddgGlobals.importKey('raw', keyBuffer, 'AES-GCM', false, ['encrypt'])

                const encrypt = (message) => {
                  let enc = new ddgGlobals.TextEncoder()
                  return ddgGlobals.encrypt(
                      {
                          name: 'AES-GCM',
                          iv
                      },
                      key,
                      enc.encode(message)
                  )
                }

                encrypt(ddgGlobals.JSONstringify(message)).then((encryptedMsg) =>
                      window[messageHandling.methodName](encryptedMsg))
            })()
            """

            message.webView?.evaluateJavaScript(script)
        }
    }

}
