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
    func requestResizeToSize(width: CGFloat, height: CGFloat)
}

public protocol AutofillMessagingToChildDelegate {
    var lastOpenHost: String? { get }
    func messageSelectedCredential(_ data: [String: String], _ configType: String)
    func close()
}

public protocol ContentOverlayGetterDelegate: AnyObject {
    var view: NSView { get }
    var contentOverlayPopover: AutofillOverlayDelegate { get }
}

public class AutofillUserScript: NSObject, UserScript {

    typealias MessageReplyHandler = (String?) -> Void
    typealias MessageHandler = (AutofillMessage, @escaping MessageReplyHandler) -> Void

    public var lastOpenHost: String?
    public var contentOverlay: AutofillUserScriptDelegate?
    // Used as a message channel from parent WebView to the relevant in page AutofillUserScript
    public var autofillInterfaceToChild: AutofillMessagingToChildDelegate?
    func hostForMessage(_ message: AutofillMessage) -> String {
        if topAutofill {
            return autofillInterfaceToChild?.lastOpenHost ?? ""
        } else {
            return hostProvider.hostForMessage(message)
        }
    }

    private enum MessageName: String, CaseIterable {
#if !os(iOS)
        case setSize
        case selectedDetail
        case closeAutofillParent

        case getSelectedCredentials
        case showAutofillParent
#endif
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

    public var topAutofill: Bool
    #if !os(iOS)
    var selectedCredential: [String: String]?
    var selectedConfigType: String?
    public weak var currentOverlayTab: AutofillOverlayDelegate?
    #endif
    public var clickPoint: CGPoint?
    public var serializedInputContext: String?

    public weak var emailDelegate: AutofillEmailDelegate?
    public weak var vaultDelegate: AutofillSecureVaultDelegate?
    
    private var scriptSourceProvider: AutofillUserScriptSourceProvider

    public lazy var source: String = {
        var js = scriptSourceProvider.source
        js = js.replacingOccurrences(of: "PLACEHOLDER_SECRET", with: generatedSecret)
        js = js.replacingOccurrences(of: "// INJECT isTopFrame HERE", with: "isTopFrame = \(topAutofill ? "true" : "false");")
        return js
    }()

    public var injectionTime: WKUserScriptInjectionTime { .atDocumentStart }
    public var forMainFrameOnly: Bool {
        if topAutofill { return true }
        if #available(iOS 14, macOS 11, *) {
            return false
        }
        // We can't do reply based messaging to frames on versions before the ones mentioned above, so main frame only
        return true
    }
    public var messageNames: [String] { MessageName.allCases.map(\.rawValue) }

    private func messageHandlerFor(_ message: MessageName) -> MessageHandler {
        switch message {
#if !os(iOS)
        // Top Autofill specific messages
        case .setSize: return setSize
        case .selectedDetail: return selectedDetail

        // Child Autofill specific messages
        case .getSelectedCredentials: return getSelectedCredentials
        case .showAutofillParent: return showAutofillParent

        // For child and parent autofill
        case .closeAutofillParent: return closeAutofillParent
#endif

        // Generic Autofill messages
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

    func setSize(_ message: AutofillMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let width = dict["width"] as? CGFloat,
              let height = dict["height"] as? CGFloat else {
                  return replyHandler(nil)
              }
        self.contentOverlay?.requestResizeToSize(width: width, height: height)
        replyHandler(nil)
    }

    /* Called from top context */
    func selectedDetail(_ message: AutofillMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let chosenCredential = dict["data"] as? [String: String],
              let configType = dict["configType"] as? String,
              let autofillInterfaceToChild = autofillInterfaceToChild else { return }
        autofillInterfaceToChild.messageSelectedCredential(chosenCredential, configType)
    }

    struct GetSelectedCredentialsResponse: Encodable {
        var type: String
        var data: [String: String]?
        var configType: String?
    }

    let encrypter: AutofillEncrypter
    let hostProvider: AutofillHostProvider
    let generatedSecret: String = UUID().uuidString

    init(scriptSourceProvider: AutofillUserScriptSourceProvider,
         encrypter: AutofillEncrypter = AESGCMAutofillEncrypter(),
         hostProvider: SecurityOriginHostProvider = SecurityOriginHostProvider()) {
        self.scriptSourceProvider = scriptSourceProvider
        self.hostProvider = hostProvider
        self.encrypter = encrypter
        self.topAutofill = false
    }
    
    public convenience init(scriptSourceProvider: AutofillUserScriptSourceProvider) {
        self.init(scriptSourceProvider: scriptSourceProvider,
                  encrypter: AESGCMAutofillEncrypter(),
                  hostProvider: SecurityOriginHostProvider())
    }

    public convenience init(scriptSourceProvider: AutofillUserScriptSourceProvider, overlay: AutofillUserScriptDelegate) {
        self.init(scriptSourceProvider: scriptSourceProvider, encrypter: AESGCMAutofillEncrypter(), hostProvider: SecurityOriginHostProvider())
        self.topAutofill = true
        self.contentOverlay = overlay
    }

}

#if !os(iOS)
public protocol AutofillOverlayDelegate: AnyObject {
    var view: NSView { get }
    func autofillCloseOverlay(_ autofillUserScript: AutofillMessagingToChildDelegate?)
    func autofillDisplayOverlay(_ messageInterface: AutofillMessagingToChildDelegate, of: NSView, serializedInputContext: String, click: CGPoint, inputPosition: CGRect)
}

extension AutofillUserScript: AutofillMessagingToChildDelegate {
    /* Called from the child autofill */
    func getSelectedCredentials(_ message: AutofillMessage, _ replyHandler: MessageReplyHandler) {
        var response = GetSelectedCredentialsResponse(type: "none")
        if lastOpenHost == nil || message.messageHost != lastOpenHost {
            response = GetSelectedCredentialsResponse(type: "stop")
        } else if let selectedCredential = selectedCredential {
            response = GetSelectedCredentialsResponse(type: "ok", data: selectedCredential, configType: selectedConfigType)
            clearSelectedCredentials()
        }
        if let json = try? JSONEncoder().encode(response),
           let jsonString = String(data: json, encoding: .utf8) {
            replyHandler(jsonString)
        }
    }
    
    func closeAutofillParent(_ message: AutofillMessage, _ replyHandler: MessageReplyHandler) {
        if topAutofill {
            guard let autofillInterfaceToChild = autofillInterfaceToChild else { return }
            self.contentOverlay?.requestResizeToSize(width: 0, height: 0)
            autofillInterfaceToChild.close()
            replyHandler(nil)
        } else {
            close()
            replyHandler(nil)
        }
    }
    
    public func messageSelectedCredential(_ data: [String: String], _ configType: String) {
        guard let currentOverlayTab = currentOverlayTab else { return }
        currentOverlayTab.autofillCloseOverlay(self)
        selectedCredential = data
        selectedConfigType = configType
    }

    func clearSelectedCredentials() {
        selectedCredential = nil
        selectedConfigType = nil
    }

    public func close() {
        guard let currentOverlayTab = currentOverlayTab else { return }
        currentOverlayTab.autofillCloseOverlay(self)
        clearSelectedCredentials()
        lastOpenHost = nil
    }

    func showAutofillParent(_ message: AutofillMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let left = dict["inputLeft"] as? CGFloat,
              let top = dict["inputTop"] as? CGFloat,
              let height = dict["inputHeight"] as? CGFloat,
              let width = dict["inputWidth"] as? CGFloat,
              let serializedInputContext = dict["serializedInputContext"] as? String,
              let currentOverlayTab = currentOverlayTab,
              let clickPoint = clickPoint else {
                  return
              }
        // Sets the last message host, so we can check when it messages back
        lastOpenHost = hostProvider.hostForMessage(message)

        currentOverlayTab.autofillDisplayOverlay(self,
                                                 of: currentOverlayTab.view,
                                                 serializedInputContext: serializedInputContext,
                                                 click: clickPoint,
                                                 inputPosition: CGRect(x: left, y: top, width: width, height: height))
        replyHandler(nil)
    }
}
#endif

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
    
    func processMessage(_ userContentController: WKUserContentController, didReceive message: AutofillMessage) {
        guard let messageName = MessageName(rawValue: message.messageName),
              let body = message.messageBody as? [String: Any],
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

            assert(message.messageWebView != nil)
            dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
            message.messageWebView?.evaluateJavaScript(script)
        }
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        processMessage(userContentController, didReceive: message)
    }

}
