//
//  TopAutofillUserScript+Email.swift
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

public protocol TopAutofillEmailDelegate: AnyObject {

    func topAutofillUserScript(_: TopAutofillUserScript,
                            didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                            shouldConsumeAliasIfProvided: Bool,
                            completionHandler: @escaping AliasCompletion)
    func topAutofillUserScriptDidRequestRefreshAlias(_ : TopAutofillUserScript)
    func topAutofillUserScript(_: TopAutofillUserScript, didRequestStoreToken token: String, username: String, cohort: String?)
    func topAutofillUserScriptDidRequestUsernameAndAlias(_ : TopAutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion)
    func topAutofillUserScriptDidRequestSignedInStatus(_: TopAutofillUserScript) -> Bool

}

extension TopAutofillUserScript {

    func emailCheckSignedInStatus(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        let signedIn = emailDelegate?.topAutofillUserScriptDidRequestSignedInStatus(self) ?? false
        let signedInString = String(signedIn)
        replyHandler("""
            { "isAppSignedIn": \(signedInString) }
        """)
    }

    func emailStoreToken(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let token = dict["token"] as? String,
              let username = dict["username"] as? String else { return }
        let cohort = dict["cohort"] as? String
        emailDelegate?.topAutofillUserScript(self, didRequestStoreToken: token, username: username, cohort: cohort)
        replyHandler(nil)
    }

    func emailGetAlias(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let requiresUserPermission = dict["requiresUserPermission"] as? Bool,
              let shouldConsumeAliasIfProvided = dict["shouldConsumeAliasIfProvided"] as? Bool else { return }

        emailDelegate?.topAutofillUserScript(self,
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

    func emailRefreshAlias(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        emailDelegate?.topAutofillUserScriptDidRequestRefreshAlias(self)
        replyHandler(nil)
    }

    func emailGetAddresses(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        print("got outer topAutofillUserScriptDidRequestUsernameAndAlias")
        emailDelegate?.topAutofillUserScriptDidRequestUsernameAndAlias(self) { username, alias, _ in
            print("got inner topAutofillUserScriptDidRequestUsernameAndAlias")
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
