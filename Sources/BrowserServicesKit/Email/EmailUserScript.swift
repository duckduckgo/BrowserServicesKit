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

public protocol EmailUserScriptDelegate: AnyObject {
    func emailUserScript(_ emailUserScript: EmailUserScript,
                         didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                         shouldConsumeAliasIfProvided: Bool,
                         completionHandler: @escaping AliasCompletion)
    func emailUserScriptDidRequestRefreshAlias(emailUserScript: EmailUserScript)
    func emailUserScript(_ emailUserScript: EmailUserScript, didRequestStoreToken token: String, username: String)
    func emailUserScriptDidRequestUsernameAndAlias(emailUserScript: EmailUserScript, completionHandler: @escaping UsernameAndAliasCompletion)
}

public class EmailUserScript: NSObject, UserScript {
    
    private enum EmailMessageNames: String, CaseIterable {
        case storeToken = "emailHandlerStoreToken"
        case getAlias = "emailHandlerGetAlias"
        case refreshAlias = "emailHandlerRefreshAlias"
        case getAddresses = "emailHandlerGetAddresses"
    }
    
    public weak var delegate: EmailUserScriptDelegate?
    public var webView: WKWebView?
    
    public lazy var source: String = {
        #if os(OSX)
            let replacements = ["// INJECT isApp HERE": "isApp = true;"]
        #else
            let replacements: [String: String] = [:]
        #endif
        return EmailUserScript.loadJS("autofill", from: Bundle.module, withReplacements: replacements)
    }()
    public var injectionTime: WKUserScriptInjectionTime { .atDocumentEnd }
    public var forMainFrameOnly: Bool { false }
    public var messageNames: [String] { EmailMessageNames.allCases.map(\.rawValue) }
        
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let type = EmailMessageNames(rawValue: message.name) else { return }
        
        switch type {
        case .storeToken:
            guard let dict = message.body as? [String: Any],
                  let token = dict["token"] as? String,
                  let username = dict["username"] as? String else { return }
            delegate?.emailUserScript(self, didRequestStoreToken: token, username: username)

        case .getAlias:
            guard let dict = message.body as? [String: Any],
                  let requiresUserPermission = dict["requiresUserPermission"] as? Bool,
                  let shouldConsumeAliasIfProvided = dict["shouldConsumeAliasIfProvided"] as? Bool else { return }

            delegate?.emailUserScript(self,
                                      didRequestAliasAndRequiresUserPermission: requiresUserPermission,
                                      shouldConsumeAliasIfProvided: shouldConsumeAliasIfProvided) { alias, _ in
                guard let alias = alias else {
                    return
                }
                let jsString = EmailUserScript.postMessageJSString(withPropertyString: "type: 'getAliasResponse', alias: \"\(alias)\"")
                self.webView?.evaluateJavaScript(jsString)
            }
        case .refreshAlias:
            delegate?.emailUserScriptDidRequestRefreshAlias(emailUserScript: self)

        case .getAddresses:
            delegate?.emailUserScriptDidRequestUsernameAndAlias(emailUserScript: self) { username, alias, _ in
                let addresses: String
                if let username = username, let alias = alias {
                    addresses = "{ personalAddress: \"\(username)\", privateAddress: \"\(alias)\" }"
                } else {
                    addresses = "null"
                }

                let jsString = EmailUserScript.postMessageJSString(withPropertyString: "type: 'getAddressesResponse', addresses: \(addresses)")
                self.webView?.evaluateJavaScript(jsString)
            }
        }
    }
    
    private static func postMessageJSString(withPropertyString propertyString: String) -> String {
        let string = "window.postMessage({%@, fromIOSApp: true}, window.origin)"
        return String(format: string, propertyString)
    }
}
