//
//  AutofillUserScript+Email.swift
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

extension AutofillUserScript {


    func emailCheckSignedInStatus(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        let signedIn = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        let signedInString = String(signedIn)
        replyHandler("""
            { "isAppSignedIn": \(signedInString) }
        """)
    }

    func emailStoreToken(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.body as? [String: Any],
              let token = dict["token"] as? String,
              let username = dict["username"] as? String else { return }
        emailDelegate?.autofillUserScript(self, didRequestStoreToken: token, username: username)
        replyHandler(nil)
    }

    func emailGetAlias(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
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

    func emailRefreshAlias(_ message: WKScriptMessage, _ replyHandler: MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestRefreshAlias(self)
        replyHandler(nil)
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


}
