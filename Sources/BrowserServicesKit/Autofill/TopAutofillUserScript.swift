//
//  TopAutofillUserScript.swift
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

public protocol TopAutofillUserScriptDelegate: AnyObject {

    func clickTriggered(_ script: TopAutofillUserScript)

}

public class TopAutofillUserScript: NSObject, UserScript {
    
    
    public var messageInterfaceBack: AutofillMessaging?
    
    func hostForMessage() -> String {
        messageInterfaceBack?.lastOpenHost ?? ""
    }

    private enum MessageName: String, CaseIterable {
        case selectedDetail

        case emailHandlerStoreToken
        case emailHandlerGetAlias
        case emailHandlerRefreshAlias
        case emailHandlerGetAddresses
        case emailHandlerCheckAppSignedInStatus

        case pmHandlerGetAutofillInitData

        case pmHandlerStoreCredentials
        case pmHandlerGetAccounts
        case pmHandlerGetAutofillCredentials
        case pmHandlerGetIdentity
        case pmHandlerGetCreditCard

        case pmHandlerOpenManageCreditCards
        case pmHandlerOpenManageIdentities
        case pmHandlerOpenManagePasswords

    }
    
    public var messageNames: [String] { MessageName.allCases.map(\.rawValue) }

    private func messageHandlerFor(_ message: MessageName) -> MessageHandler {
        print("got top message \(message)")
        switch message {
            
        case .selectedDetail: return selectedDetail

        case .emailHandlerStoreToken: return emailStoreToken
        case .emailHandlerGetAlias: return emailGetAlias
        case .emailHandlerRefreshAlias: return emailRefreshAlias
        case .emailHandlerGetAddresses: return emailGetAddresses
        case .emailHandlerCheckAppSignedInStatus: return emailCheckSignedInStatus

        case .pmHandlerGetAutofillInitData: return pmGetAutoFillInitData

        case .pmHandlerStoreCredentials: return pmStoreCredentials
        case .pmHandlerGetAccounts: return pmGetAccounts
        case .pmHandlerGetAutofillCredentials: return pmGetAutofillCredentials

        case .pmHandlerGetIdentity: return pmGetIdentity
        case .pmHandlerGetCreditCard: return pmGetCreditCard

        case .pmHandlerOpenManageCreditCards: return pmOpenManageCreditCards
        case .pmHandlerOpenManageIdentities: return pmOpenManageIdentities
        case .pmHandlerOpenManagePasswords: return pmOpenManagePasswords

        }
    }
    
    public weak var emailDelegate: TopAutofillEmailDelegate?
    public weak var vaultDelegate: TopAutofillSecureVaultDelegate?
    public var inputType: String?
    let hostProvider: AutofillHostProvider
    let generatedSecret: String = UUID().uuidString
    let encrypter: AutofillEncrypter
    
    func selectedDetail(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let chosenCredential = dict["data"] as? [String: String],
              let configType = dict["configType"] as? String else { return }
        messageInterfaceBack!.messageSelectedCredential(chosenCredential, configType)
    }

    typealias MessageReplyHandler = (String?) -> Void
    typealias MessageHandler = (WKScriptMessage, @escaping MessageReplyHandler) -> Void

    public lazy var source: String = {
        var replacements: [String: String] = [:]
        #if os(macOS)
            replacements["// INJECT isApp HERE"] = "isApp = true;"
            replacements["// INJECT isTopFrame HERE"] = "isTopFrame = true;"
        #endif

        if #available(iOS 14, macOS 11, *) {
            replacements["// INJECT hasModernWebkitAPI HERE"] = "hasModernWebkitAPI = true;"
        } else {
            replacements["PLACEHOLDER_SECRET"] = generatedSecret
        }

        return TopAutofillUserScript.loadJS("topAutofill", from: Bundle.module, withReplacements: replacements)
    }()

    public var injectionTime: WKUserScriptInjectionTime { .atDocumentStart }
    public var forMainFrameOnly: Bool {
        return true
    }
    
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
extension TopAutofillUserScript: WKScriptMessageHandlerWithReply {

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage,
                                      replyHandler: @escaping (Any?, String?) -> Void) {
        guard let messageName = MessageName(rawValue: message.name) else { return }
        print("got top mesage \(messageName)")

        messageHandlerFor(messageName)(message) {
            replyHandler($0, nil)
        }

    }

}

// Fallback for older iOS / macOS version
extension TopAutofillUserScript {

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("got top mesage", message)
        guard let messageName = MessageName(rawValue: message.name),
              let body = message.body as? [String: Any],
              let messageHandling = body["messageHandling"] as? [String: Any],
              let secret = messageHandling["secret"] as? String,
              // If this does not match the page is playing shenanigans.
              secret == generatedSecret
        else { return }
        print("got top mesage \(messageName)")

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
