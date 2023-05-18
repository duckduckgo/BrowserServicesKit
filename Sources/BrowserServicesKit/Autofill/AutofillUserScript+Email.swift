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
import UserScript

public protocol AutofillEmailDelegate: AnyObject {

    func autofillUserScript(_: AutofillUserScript,
                            didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                            shouldConsumeAliasIfProvided: Bool,
                            completionHandler: @escaping AliasCompletion)
    func autofillUserScriptDidRequestRefreshAlias(_ : AutofillUserScript)
    func autofillUserScript(_: AutofillUserScript, didRequestStoreToken token: String, username: String, cohort: String?)
    func autofillUserScriptDidRequestUsernameAndAlias(_ : AutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion)
    func autofillUserScriptDidRequestUserData(_ : AutofillUserScript, completionHandler: @escaping UserDataCompletion)
    func autofillUserScriptDidRequestSignOut(_ : AutofillUserScript)
    func autofillUserScriptDidRequestSignedInStatus(_: AutofillUserScript) -> Bool
    func autofillUserScript(_ : AutofillUserScript, didRequestSetInContextPromptValue value: Double)
    func autofillUserScriptDidRequestInContextPromptValue(_ : AutofillUserScript) -> Double?

}

extension AutofillUserScript {

    func emailCheckSignedInStatus(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        let signedIn = emailDelegate?.autofillUserScriptDidRequestSignedInStatus(self) ?? false
        let signedInString = String(signedIn)
        replyHandler("""
            { "isAppSignedIn": \(signedInString) }
        """)
    }

    func emailStoreToken(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let token = dict["token"] as? String,
              let username = dict["username"] as? String else { return }
        let cohort = dict["cohort"] as? String
        emailDelegate?.autofillUserScript(self, didRequestStoreToken: token, username: username, cohort: cohort)
        replyHandler(nil)
    }

    func emailRemoveToken(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestSignOut(self)
        replyHandler(nil)
    }

    func emailGetAlias(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
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

    func emailRefreshAlias(_ message: UserScriptMessage, _ replyHandler: MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestRefreshAlias(self)
        replyHandler(nil)
    }

    func emailGetAddresses(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
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

    private struct UserData: Encodable {
        public let userName: String
        public let nextAlias: String
        public let token: String
    }

    func emailGetUserData(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        emailDelegate?.autofillUserScriptDidRequestUserData(self) { username, alias, token, _ in
            if let username = username, let alias = alias, let token = token {

                let userData = UserData(userName: username, nextAlias: alias, token: token)
                if let json = try? JSONEncoder().encode(userData), let jsonString = String(data: json, encoding: .utf8) {
                    replyHandler(jsonString)
                } else {
                    replyHandler(nil)
                }

            } else {
                replyHandler(nil)
            }
        }
    }

    private struct DeviceEmailCapabilities: Encodable {
        public let addUserData: Bool
        public let getUserData: Bool
        public let removeUserData: Bool
    }

    func emailGetDeviceCapabilities(_ message: UserScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        let capabilities = DeviceEmailCapabilities(addUserData: true, getUserData: true, removeUserData: true)
        if let json = try? JSONEncoder().encode(capabilities), let jsonString = String(data: json, encoding: .utf8) {
            replyHandler(jsonString)
        } else {
            replyHandler(nil)
        }
    }

    // MARK: In Context Email Protection

    func setInContextSignupPermanentlyDismissedAt(_ message: UserScriptMessage, replyHandler: @escaping MessageReplyHandler) {
        guard let body = message.messageBody as? [String: Any],
              let value = body["value"] as? Double else {
            return
        }
        emailDelegate?.autofillUserScript(self, didRequestSetInContextPromptValue: value)
        print(">> AB: setIncontextSignupPermanentlyDismissedAt", value)
        replyHandler(nil)
    }

    func getInContextSignupDismissedAt(_ message: UserScriptMessage, replyHandler: @escaping MessageReplyHandler) {
        // AB-TODO: Implement
        let inContextEmailSignupPromptDismissedPermanentlyAt: Double? = emailDelegate?.autofillUserScriptDidRequestInContextPromptValue(self)
        let inContextSignupDismissedAt = IncontextSignupDismissedAt(
            permanentlyDismissedAt: inContextEmailSignupPromptDismissedPermanentlyAt
        )
        let response = GetIncontextSignupDismissedAtResponse(success: inContextSignupDismissedAt)

        if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
            print(">> AB: GET getIncontextSignupDismissedAt", jsonString)
            replyHandler(jsonString)
        }
    }

    func startEmailProtectionSignup(_ message: UserScriptMessage, replyHandler: @escaping MessageReplyHandler) {
        // AB-TODO: Implement
        print(">> AB: startEmailProtectionSignup")
        NotificationCenter.default.post(name: .emailDidIncontextSignup, object: self)
        replyHandler(nil)
    }

    func closeEmailProtectionTab(_ message: UserScriptMessage, replyHandler: @escaping MessageReplyHandler) {
        // AB-TODO: Implement
        print(">> AB: closeEmailProtectionTab")
        NotificationCenter.default.post(name: .emailDidCloseEmailProtection, object: self)
        replyHandler(nil)
    }

}
