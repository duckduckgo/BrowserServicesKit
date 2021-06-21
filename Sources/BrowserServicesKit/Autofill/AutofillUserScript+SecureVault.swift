//
//  AutofillUserScript+SecureVault.swift
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

public protocol AutofillSecureVaultDelegate: AnyObject {

    func autofillUserScript(_: AutofillUserScript, didRequestPasswordManagerForDomain domain: String)
    func autofillUserScript(_: AutofillUserScript, didRequestStoreCredentialsForDomain domain: String, username: String, password: String)
    func autofillUserScript(_: AutofillUserScript, didRequestAccountsForDomain domain: String,
                            completionHandler: @escaping ([SecureVaultModels.WebsiteAccount]) -> Void)
    func autofillUserScript(_: AutofillUserScript, didRequestCredentialsForAccount accountId: Int64,
                            completionHandler: @escaping (SecureVaultModels.WebsiteCredentials?) -> Void)

}

extension AutofillUserScript {

    struct RequestVaultAccountsResponse: Codable {

        struct Account: Codable {
            let id: Int64
            let username: String
            let lastUpdated: TimeInterval
        }

        let success: [Account]
    }

    struct RequestVaultCredentialsResponse: Codable {

        struct Credential: Codable {
            let id: Int64
            let username: String
            let password: String
            let lastUpdated: TimeInterval
        }

        let success: Credential

    }

    func pmStoreCredentials(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        defer {
            replyHandler(nil)
        }

        guard let body = message.body as? [String: Any],
              let username = body["username"] as? String,
              let password = body["password"] as? String else {
            return
        }

        let domain = hostProvider.hostForMessage(message)
        vaultDelegate?.autofillUserScript(self, didRequestStoreCredentialsForDomain: domain, username: username, password: password)
    }

    func pmGetAccounts(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {

        vaultDelegate?.autofillUserScript(self, didRequestAccountsForDomain: hostProvider.hostForMessage(message)) { credentials in
            let credentials: [RequestVaultAccountsResponse.Account] = credentials.compactMap {
                guard let id = $0.id else { return nil }
                return .init(id: id, username: $0.username, lastUpdated: $0.lastUpdated.timeIntervalSince1970)
            }

            let response = RequestVaultAccountsResponse(success: credentials)
            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }

    }

    func pmGetAutofillCredentials(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {

        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let accountId = Int64(id) else {
            return
        }

        vaultDelegate?.autofillUserScript(self, didRequestCredentialsForAccount: Int64(accountId)) {
            guard let credential = $0,
                  let id = credential.account.id,
                  let password = String(data: credential.password, encoding: .utf8) else { return }

            let response = RequestVaultCredentialsResponse(success: .init(id: id,
                                                                     username: credential.account.username,
                                                                     password: password,
                                                                     lastUpdated: credential.account.lastUpdated.timeIntervalSince1970))
            if let json = try? JSONEncoder().encode(response), let jsonString = String(data: json, encoding: .utf8) {
                replyHandler(jsonString)
            }
        }
    }

    func pmOpenManagePasswords(_ message: WKScriptMessage, _ replyHandler: @escaping MessageReplyHandler) {
        vaultDelegate?.autofillUserScript(self, didRequestPasswordManagerForDomain: hostProvider.hostForMessage(message))
        replyHandler(nil)
    }

}
