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
}

public class AutofillUserScript: NSObject, UserScript {

    typealias MessageHandler = (WKScriptMessage) -> Void

    public weak var emailDelegate: AutofillEmailDelegate?
    public var webView: WKWebView?
    
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
        "emailHandlerStoreToken": emailStoreToken(_:),
        "emailHandlerGetAlias": emailGetAlias(_:),
        "emailHandlerRefreshAlias": emailRefreshAlias(_:),
        "emailHandlerGetAddresses": emailGetAddresses(_:)
    ] }()

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        messages[message.name]?(message)
    }

    private func emailStoreToken(_ message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let token = dict["token"] as? String,
              let username = dict["username"] as? String else { return }
        emailDelegate?.autofillUserScript(self, didRequestStoreToken: token, username: username)
    }

    private func emailGetAlias(_ message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let requiresUserPermission = dict["requiresUserPermission"] as? Bool,
              let shouldConsumeAliasIfProvided = dict["shouldConsumeAliasIfProvided"] as? Bool else { return }

        emailDelegate?.autofillUserScript(self,
                                  didRequestAliasAndRequiresUserPermission: requiresUserPermission,
                                  shouldConsumeAliasIfProvided: shouldConsumeAliasIfProvided) { alias, _ in
            guard let alias = alias else { return }
            let jsString = Self.postMessageJSString(withPropertyString: "type: '\(message.responseType)', alias: \"\(alias)\"")
            self.webView?.evaluateJavaScript(jsString)
        }
    }

    private func emailRefreshAlias(_ message: WKScriptMessage) {
        emailDelegate?.autofillUserScriptDidRequestRefreshAlias(self)
    }

    private func emailGetAddresses(_ message: WKScriptMessage) {
        emailDelegate?.autofillUserScriptDidRequestUsernameAndAlias(self) { username, alias, _ in
            let addresses: String
            if let username = username, let alias = alias {
                addresses = "{ personalAddress: \"\(username)\", privateAddress: \"\(alias)\" }"
            } else {
                addresses = "null"
            }

            let jsString = Self.postMessageJSString(withPropertyString: "type: '\(message.responseType)', addresses: \(addresses)")
            self.webView?.evaluateJavaScript(jsString)
        }
    }

    private static func postMessageJSString(withPropertyString propertyString: String) -> String {
        let string = "window.postMessage({%@, fromIOSApp: true}, window.origin)"
        return String(format: string, propertyString)
    }

}

extension WKScriptMessage {

    var responseType: String {
        return name + "Response"
    }

}
