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
import os.log

public class AutofillUserScript: NSObject, UserScript {

    typealias MessageReplyHandler = (String?) -> Void
    typealias MessageHandler = (AutofillMessage, @escaping MessageReplyHandler) -> Void

    internal enum MessageName: String, CaseIterable {
        case emailHandlerStoreToken
        case emailHandlerRemoveToken
        case emailHandlerGetAlias
        case emailHandlerGetUserData
        case emailHandlerGetCapabilities
        case emailHandlerRefreshAlias

        case emailHandlerGetAddresses
        case emailHandlerCheckAppSignedInStatus

        case pmHandlerGetAutofillInitData

        case pmHandlerStoreData
        case pmHandlerGetAccounts
        case pmHandlerGetAutofillCredentials
        case pmHandlerGetIdentity
        case pmHandlerGetCreditCard

        case pmHandlerOpenManageCreditCards
        case pmHandlerOpenManageIdentities
        case pmHandlerOpenManagePasswords

        case getAvailableInputTypes
        case getAutofillData
        case storeFormData
        
        case askToUnlockProvider
        case checkCredentialsProviderStatus
    }

    /// Represents if the autofill is loaded into the top autofill context.
    public var isTopAutofillContext: Bool
    /// Serialized JSON string of any format to be passed from child to parent autofill.
    ///  once the user selects a field to open, we store field type and other contextual information to be initialized into the top autofill.
    public var serializedInputContext: String?

    public weak var emailDelegate: AutofillEmailDelegate?
    public weak var vaultDelegate: AutofillSecureVaultDelegate?

    internal var scriptSourceProvider: AutofillUserScriptSourceProvider

    public lazy var source: String = {
        var js = scriptSourceProvider.source
        js = js.replacingOccurrences(of: "PLACEHOLDER_SECRET", with: generatedSecret)
        js = js.replacingOccurrences(of: "// INJECT webkitMessageHandlerNames HERE", with: "webkitMessageHandlerNames = \(messageNamesJson);")
        js = js.replacingOccurrences(of: "// INJECT isTopFrame HERE", with: "isTopFrame = \(isTopAutofillContext ? "true" : "false");")
        return js
    }()

    public var injectionTime: WKUserScriptInjectionTime { .atDocumentStart }
    public var forMainFrameOnly: Bool {
        if isTopAutofillContext { return true }
        if #available(iOS 14, macOS 11, *) {
            return false
        }
        // We can't do reply based messaging to frames on versions before the ones mentioned above, so main frame only
        return true
    }

    public var messageNames: [String] {
        return MessageName.allCases.map(\.rawValue)
    }

    // communicate known message handler names to user scripts.
    public lazy var messageNamesJson: String = {
        // note: this doesn't include the messages from the overlay - only messages that can potentially be execute on macOS 10.x need
        // to be communicated to the JavaScript layer.
        let combinedMessages = MessageName.allCases.map(\.rawValue) + WebsiteAutofillUserScript.WebsiteAutofillMessageName.allCases.map(\.rawValue)
        guard let json = try? JSONEncoder().encode(combinedMessages), let jsonString = String(data: json, encoding: .utf8) else {
            assertionFailure("AutofillUserScript: could not encode message names into JSON")
            return ""
        }
        return jsonString
    }()

    // swiftlint:disable cyclomatic_complexity
    internal func messageHandlerFor(_ messageName: String) -> MessageHandler? {
        guard let message = MessageName(rawValue: messageName) else {
            os_log("Failed to parse Autofill User Script message: '%{public}s'", log: .userScripts, type: .debug, messageName)
            return nil
        }
        
        os_log("AutofillUserScript: received '%{public}s'", log: .userScripts, type: .debug, messageName)

        switch message {
        case .emailHandlerStoreToken: return emailStoreToken
        case .emailHandlerRemoveToken: return emailRemoveToken
        case .emailHandlerGetAlias: return emailGetAlias
        case .emailHandlerGetUserData: return emailGetUserData
        case .emailHandlerGetCapabilities: return emailGetDeviceCapabilities
        case .emailHandlerRefreshAlias: return emailRefreshAlias
        case .emailHandlerGetAddresses: return emailGetAddresses
        case .emailHandlerCheckAppSignedInStatus: return emailCheckSignedInStatus

        case .pmHandlerGetAutofillInitData: return pmGetAutoFillInitData
            
        case .getAvailableInputTypes: return getAvailableInputTypes
        case .getAutofillData: return getAutofillData
        case .storeFormData: return pmStoreData

        case .pmHandlerStoreData: return pmStoreData
        case .pmHandlerGetAccounts: return pmGetAccounts
        case .pmHandlerGetAutofillCredentials: return pmGetAutofillCredentials
        case .pmHandlerGetIdentity: return pmGetIdentity
        case .pmHandlerGetCreditCard: return pmGetCreditCard

        case .pmHandlerOpenManageCreditCards: return pmOpenManageCreditCards
        case .pmHandlerOpenManageIdentities: return pmOpenManageIdentities
        case .pmHandlerOpenManagePasswords: return pmOpenManagePasswords
            
        case .askToUnlockProvider: return askToUnlockProvider
        case .checkCredentialsProviderStatus: return checkCredentialsProviderStatus
        }
    }
    // swiftlint:enable cyclomatic_complexity

    let encrypter: AutofillEncrypter
    let hostProvider: AutofillHostProvider
    let generatedSecret: String = UUID().uuidString
    func hostForMessage(_ message: AutofillMessage) -> String {
        return hostProvider.hostForMessage(message)
    }

    public convenience init(scriptSourceProvider: AutofillUserScriptSourceProvider) {
        self.init(scriptSourceProvider: scriptSourceProvider,
                  encrypter: AESGCMAutofillEncrypter(),
                  hostProvider: SecurityOriginHostProvider())
    }

    init(scriptSourceProvider: AutofillUserScriptSourceProvider,
         encrypter: AutofillEncrypter = AESGCMAutofillEncrypter(),
         hostProvider: SecurityOriginHostProvider = SecurityOriginHostProvider()) {
        self.scriptSourceProvider = scriptSourceProvider
        self.hostProvider = hostProvider
        self.encrypter = encrypter
        self.isTopAutofillContext = false
    }
}

struct GetSelectedCredentialsResponse: Encodable {
    /// Represents the mode the JS should take, valid values are 'none', 'stop', 'ok'
    var type: String
    /// Key value data passed from the JS to be retuned to the child
    var data: [String: String]?
    var configType: String?
}

/// Represents data after the user clicks to be sent back into the JS child context
struct SelectedDetailsData {
    var data: [String: String]?
    var configType: String?
}

@available(iOS 14, *)
@available(macOS 11, *)
extension AutofillUserScript: WKScriptMessageHandlerWithReply {

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage,
                                      replyHandler: @escaping (Any?, String?) -> Void) {
        guard let messageHandler = messageHandlerFor(message.name) else {
            // Unsupported message fail silently
            return
        }

        messageHandler(message) {
            replyHandler($0, nil)
        }

    }

}

// Fallback for older iOS / macOS version
extension AutofillUserScript {

    func processMessage(_ userContentController: WKUserContentController, didReceive message: AutofillMessage) {
        guard let messageHandler = messageHandlerFor(message.messageName) else {
            // Unsupported message fail silently
            return
        }

        guard let body = message.messageBody as? [String: Any],
              let messageHandling = body["messageHandling"] as? [String: Any],
              let secret = messageHandling["secret"] as? String,
              // If this does not match the page is playing shenanigans.
              secret == generatedSecret
        else { return }

        messageHandler(message) { reply in
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
