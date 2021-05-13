//
//  VaultUserScript.swift
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

import BrowserServicesKit
import WebKit

protocol VaultUserScriptDelegate: AnyObject {

    func vaultUserScript(_ userScript: VaultUserScript, requestingStoreCredentials credentials: SecureVaultModels.WebsiteCredentials)

    func vaultUserScript(_ userScript: VaultUserScript, requestingCredentialsForId id: Int64)

    func vaultUserScript(_ userScript: VaultUserScript, requestingAccountsForDomain domain: String)

}

protocol CredentialsPresenting {

    func present(accounts: [SecureVaultModels.WebsiteAccount])

    func present(credential: SecureVaultModels.WebsiteCredentials)

}

protocol DomainProviding {

    func domainFrom(message: WKScriptMessage) -> String?

}

class VaultUserScript: NSObject, UserScript {

    enum MessageNames: String, CaseIterable {

        enum RequestCredentialsArgNames: String {
            case id
        }

        enum StoreCredentialsArgNames: String {
            case username
            case password
        }

        /// Request a list of matching accounts, or the specific credentials if there's only one account.
        case vaultRequestAccounts

        /// Request the specific credentials with the given id.
        case vaultRequestCredentials

        /// Store the given credentials
        case vaultStoreCredentials

    }

    weak var delegate: VaultUserScriptDelegate?

    public lazy var source: String = {
        // return Self.loadJS("vault-support", from: Bundle.module)
        return ""
    }()

    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly: Bool = false
    let messageNames = MessageNames.allCases.map { $0.rawValue }

    let domainProvider: DomainProviding

    init(domainProvider: DomainProviding = SecurityOriginDomainProvider()) {
        self.domainProvider = domainProvider
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let type = MessageNames(rawValue: message.name) else { return }

        switch type {

        case .vaultRequestAccounts:
            guard let domain = domainProvider.domainFrom(message: message) else { return }
            delegate?.vaultUserScript(self, requestingAccountsForDomain: domain)

        case .vaultRequestCredentials:
            guard let id: Int64 = message.argument(named: MessageNames.RequestCredentialsArgNames.id.rawValue) else { return }
            delegate?.vaultUserScript(self, requestingCredentialsForId: id)

        case .vaultStoreCredentials:
            guard let username: String = message.argument(named: MessageNames.StoreCredentialsArgNames.username.rawValue),
                  let password: String = message.argument(named: MessageNames.StoreCredentialsArgNames.password.rawValue),
                  let passwordData = password.data(using: .utf8),
                  let domain = domainProvider.domainFrom(message: message) else { return }

            let account = SecureVaultModels.WebsiteAccount(username: username, domain: domain)
            let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: passwordData)
            delegate?.vaultUserScript(self, requestingStoreCredentials: credentials)

        }

    }

}

class SecurityOriginDomainProvider: DomainProviding {

    func domainFrom(message: WKScriptMessage) -> String? {
        return message.frameInfo.securityOrigin.host
    }

}

fileprivate extension WKScriptMessage {

    func argument<T>(named name: String) -> T? {
        guard let dict = body as? [String: Any] else { return nil }
        return dict[name] as? T
    }

}
