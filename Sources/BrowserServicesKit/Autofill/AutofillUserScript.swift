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
    func setSize(height: CGFloat, width: CGFloat)
}
public protocol ChildAutofillUserScriptDelegate: AnyObject {
    func clickTriggered(clickPoint: NSPoint)
}

public protocol AutofillMessaging {
    var lastOpenHost: String? { get }
    func messageSelectedCredential(_ data: [String: String], _ configType: String)
    func close()
}

public protocol OverlayProtocol {
    var view: NSView { get }
    func closeOverlay()
    func displayOverlay(rect: NSRect, of: NSView, width: CGFloat, inputType: String, messageInterface: AutofillMessaging)
}

public class AutofillUserScript: NSObject, UserScript, AutofillMessaging {

    typealias MessageReplyHandler = (String?) -> Void
    typealias MessageHandler = (WKScriptMessage, @escaping MessageReplyHandler) -> Void

    public var lastOpenHost: String?
    public var contentOverlay: AutofillUserScriptDelegate?
    public var messageInterfaceBack: AutofillMessaging?
    func hostForMessage(_ message: WKScriptMessage) -> String {
        if (topAutofill) {
            return messageInterfaceBack?.lastOpenHost ?? ""
        } else {
            return hostProvider.hostForMessage(message)
        }
    }

    private enum MessageName: String, CaseIterable {
        case setSize
        case selectedDetail
        case closeAutofillParent

        case getSelectedCredentials
        case showAutofillParent
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
    public var topView: OverlayProtocol?
    public var clickPoint: NSPoint?
    public var inputType: String?

    public weak var emailDelegate: AutofillEmailDelegate?
    public weak var vaultDelegate: AutofillSecureVaultDelegate?

    public lazy var source: String = {

        struct DDGGlobals: Codable {
            var supportsTopFrame: Bool = true;
            var isApp: Bool = true;
            var isTopFrame = false;
            var hasModernWebkitAPI = false;
            var secret: String?;
        }

        var ddgGlobals = DDGGlobals();
        var replacements: [String: String] = [:]

        #if os(macOS)
            ddgGlobals.isTopFrame = topAutofill
        #endif

        if #available(iOS 14, macOS 11, *) {
            ddgGlobals.hasModernWebkitAPI = true;
        } else {
            ddgGlobals.secret = generatedSecret;
        }
        
        var s = "((DDGGlobals) => {\n"
        s += AutofillUserScript.loadJS("autofill", from: Bundle.module, withReplacements: replacements)

        guard let json = try? JSONEncoder().encode(ddgGlobals),
           let jsonString = String(data: json, encoding: .utf8) else {
            return ""
        }

        s += ";\n})(\(jsonString));"

        return s
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
    public var requiresRunInPageContentWorld: Bool = true
    public var messageNames: [String] { MessageName.allCases.map(\.rawValue) }

    private func messageHandlerFor(_ message: MessageName) -> MessageHandler {
        switch message {
        case .setSize: return setSize
        case .selectedDetail: return selectedDetail

        case .getSelectedCredentials: return getSelectedCredentials
        case .showAutofillParent: return showAutofillParent
        case .closeAutofillParent: return closeAutofillParent
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

    func setSize(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let width = dict["width"] as? CGFloat,
              let height = dict["height"] as? CGFloat else {
                  return replyHandler(nil)
              }
        self.contentOverlay?.setSize(height: height, width: width)
        replyHandler(nil)
    }

    func selectedDetail(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let chosenCredential = dict["data"] as? [String: String],
              let configType = dict["configType"] as? String,
              let messageInterfaceBack = messageInterfaceBack else { return }
        messageInterfaceBack.messageSelectedCredential(chosenCredential, configType)
    }

    func closeAutofillParent(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        if (topAutofill) {
            guard let messageInterfaceBack = messageInterfaceBack else { return }
            self.contentOverlay?.setSize(height: 0, width: 0)
            messageInterfaceBack.close()
            replyHandler(nil)
        } else {
            guard let topView = topView else { return }
            selectedCredential = nil
            selectedConfigType = nil
            lastOpenHost = nil
            topView.closeOverlay()
            replyHandler(nil)
        }
    }

    public func messageSelectedCredential(_ data: [String: String], _ configType: String) {
        guard let topView = topView else { return }
        topView.closeOverlay()
        selectedCredential = data
        selectedConfigType = configType
    }

    public func close() {
        guard let topView = topView else { return }
        topView.closeOverlay()
        // TODO cleanup injected script
    }

    var selectedCredential: [String: String]?
    var selectedConfigType: String?

    func showAutofillParent(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
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
        // Sets the last message host, so we can check when it messages back
        lastOpenHost = hostProvider.hostForMessage(message)

        let zf = 1.0 //popover.zoomFactor!
        // Combines native click with offset of dax click.
        let clickX = CGFloat(clickPoint.x);
        let clickY = CGFloat(clickPoint.y);
        let y = (clickY - (height - top)) * zf;
        let x = (clickX - left) * zf;
        var rectWidth = width * zf
        // If the field is wider we want to left assign the rectangle anchoring
        if (width > 315) {
            rectWidth = 315 * zf
        }
        let rect = NSRect(x: x, y: y, width: rectWidth, height: height * zf)
        // TODO make 315 a constant
        if (width < 315) {
            width = 315
        }
        topView.displayOverlay(rect: rect, of: topView.view, width: width, inputType: inputType, messageInterface: self)
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
        self.topAutofill = false
    }

    public convenience override init() {
        self.init(encrypter: AESGCMAutofillEncrypter(), hostProvider: SecurityOriginHostProvider())
    }

    public convenience init(overlay: AutofillUserScriptDelegate) {
        self.init(encrypter: AESGCMAutofillEncrypter(), hostProvider: SecurityOriginHostProvider())
        self.topAutofill = true
        self.contentOverlay = overlay
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
