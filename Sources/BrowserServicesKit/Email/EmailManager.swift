//
//  EmailManager.swift
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

import Foundation

// swiftlint:disable file_length

public protocol EmailManagerStorage: AnyObject {
    func getUsername() -> String?
    func getToken() -> String?
    func getAlias() -> String?
    func getCohort() -> String?
    func getLastUseDate() -> String?
    func store(token: String, username: String, cohort: String?)
    func store(alias: String)
    func store(lastUseDate: String)
    func deleteAlias()
    func deleteAuthenticationState()

    // Waitlist:

    func getWaitlistToken() -> String?
    func getWaitlistTimestamp() -> Int?
    func getWaitlistInviteCode() -> String?
    func store(waitlistToken: String)
    func store(waitlistTimestamp: Int)
    func store(inviteCode: String)
    func deleteWaitlistState()
}

public enum EmailManagerPermittedAddressType {
    case user
    case generated
    case none
}

public enum EmailManagerWaitlistState {
    case notJoinedQueue
    case joinedQueue
    case inBeta
}

// swiftlint:disable identifier_name
public protocol EmailManagerAliasPermissionDelegate: AnyObject {

    func emailManager(_ emailManager: EmailManager,
                      didRequestPermissionToProvideAliasWithCompletion: @escaping (EmailManagerPermittedAddressType) -> Void)

}
// swiftlint:enable identifier_name

// swiftlint:disable function_parameter_count
public protocol EmailManagerRequestDelegate: AnyObject {
    func emailManager(_ emailManager: EmailManager,
                      requested url: URL,
                      method: String,
                      headers: [String: String],
                      parameters: [String: String]?,
                      httpBody: Data?,
                      timeoutInterval: TimeInterval,
                      completion: @escaping (Data?, Error?) -> Void)
}
// swiftlint:enable function_parameter_count

public extension Notification.Name {
    static let emailDidSignIn = Notification.Name("com.duckduckgo.browserServicesKit.EmailDidSignIn")
    static let emailDidSignOut = Notification.Name("com.duckduckgo.browserServicesKit.EmailDidSignOut")
    static let emailDidGenerateAlias = Notification.Name("com.duckduckgo.browserServicesKit.EmailDidGenerateAlias")
}

public enum AliasRequestError: Error {
    case noDataError
    case signedOut
    case invalidResponse
    case userRefused
    case permissionDelegateNil
}

public struct EmailUrls {
    struct Url {
        static let emailAlias = "https://quack.duckduckgo.com/api/email/addresses"
        static let joinWaitlist = "https://quack.duckduckgo.com/api/auth/waitlist/join"
        static let waitlistStatus = "https://quack.duckduckgo.com/api/auth/waitlist/status"
        static let getInviteCode = "https://quack.duckduckgo.com/api/auth/waitlist/code"
    }

    var emailAliasAPI: URL {
        return URL(string: Url.emailAlias)!
    }

    var joinWaitlistAPI: URL {
        return URL(string: Url.joinWaitlist)!
    }

    var waitlistStatusAPI: URL {
        return URL(string: Url.waitlistStatus)!
    }

    var getInviteCodeAPI: URL {
        return URL(string: Url.getInviteCode)!
    }
    
    public init() { }
}

public typealias AliasCompletion = (String?, AliasRequestError?) -> Void
public typealias UsernameAndAliasCompletion = (_ username: String?, _ alias: String?, AliasRequestError?) -> Void

public class EmailManager {
    
    private static let emailDomain = "duck.com"
    
    private let storage: EmailManagerStorage
    public weak var aliasPermissionDelegate: EmailManagerAliasPermissionDelegate?
    public weak var requestDelegate: EmailManagerRequestDelegate?
    
    private lazy var emailUrls = EmailUrls()
    private lazy var aliasAPIURL = emailUrls.emailAliasAPI

    private var dateFormatter = ISO8601DateFormatter()
    
    private var username: String? {
        storage.getUsername()
    }

    private var token: String? {
        storage.getToken()
    }

    private var alias: String? {
        storage.getAlias()
    }

    private var hasExistingInviteCode: Bool {
        return storage.getWaitlistInviteCode() != nil
    }

    public var cohort: String? {
        storage.getCohort()
    }

    public var lastUseDate: String {
        storage.getLastUseDate() ?? ""
    }

    public func updateLastUseDate() {
        let dateString = dateFormatter.string(from: Date())
        storage.store(lastUseDate: dateString)
    }

    public var inviteCode: String? {
        storage.getWaitlistInviteCode()
    }

    public var isSignedIn: Bool {
        return token != nil && username != nil
    }

    public var eligibleToJoinWaitlist: Bool {
        return waitlistState == .notJoinedQueue
    }

    public var isInWaitlist: Bool {
        return waitlistState == .joinedQueue && !isSignedIn
    }

    public var waitlistState: EmailManagerWaitlistState {
        if storage.getWaitlistTimestamp() != nil, storage.getWaitlistInviteCode() == nil {
            return .joinedQueue
        }

        if storage.getWaitlistInviteCode() != nil {
            return .inBeta
        }

        return .notJoinedQueue
    }
    
    public var userEmail: String? {
        guard let username = username else { return nil }
        return username + "@" + EmailManager.emailDomain
    }
    
    public init(storage: EmailManagerStorage = EmailKeychainManager()) {
        self.storage = storage

        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York") // Use ET time zone
    }
    
    public func signOut() {
        storage.deleteAuthenticationState()
        NotificationCenter.default.post(name: .emailDidSignOut, object: self)
    }

    public func emailAddressFor(_ alias: String) -> String {
        return alias + "@" + Self.emailDomain
    }

    public func getAliasIfNeededAndConsume(timeoutInterval: TimeInterval = 4.0, completionHandler: @escaping AliasCompletion) {
        getAliasIfNeeded(timeoutInterval: timeoutInterval) { [weak self] newAlias, error in
            completionHandler(newAlias, error)
            if error == nil {
                self?.consumeAliasAndReplace()
            }
        }
    }

}

extension EmailManager: AutofillEmailDelegate {

    public func autofillUserScriptDidRequestSignedInStatus(_: AutofillUserScript) -> Bool {
         return isSignedIn
    }

    public func autofillUserScriptDidRequestUsernameAndAlias(_: AutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion) {
        getAliasIfNeeded { [weak self] alias, error in
            guard let alias = alias, error == nil, let self = self else {
                completionHandler(nil, nil, error)
                return
            }

            completionHandler(self.username, alias, nil)
        }
    }
    
    public func autofillUserScript(_: AutofillUserScript,
                                   didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                                   shouldConsumeAliasIfProvided: Bool,
                                   completionHandler: @escaping AliasCompletion) {
            
        getAliasIfNeeded { [weak self] newAlias, error in
            guard let newAlias = newAlias, error == nil, let self = self else {
                completionHandler(nil, error)
                return
            }
            
            if requiresUserPermission {
                guard let delegate = self.aliasPermissionDelegate else {
                    assertionFailure("EmailUserScript requires permission to provide Alias")
                    completionHandler(nil, .permissionDelegateNil)
                    return
                }
                
                delegate.emailManager(self, didRequestPermissionToProvideAliasWithCompletion: { [weak self] permissionType in
                    switch permissionType {
                    case .user:
                        if let username = self?.username {
                            completionHandler(username, nil)
                        } else {
                            completionHandler(nil, .userRefused)
                        }
                    case .generated:
                        completionHandler(newAlias, nil)
                        if shouldConsumeAliasIfProvided {
                            self?.consumeAliasAndReplace()
                        }
                    case .none:
                        completionHandler(nil, .userRefused)
                    }
                })
            } else {
                completionHandler(newAlias, nil)
                if shouldConsumeAliasIfProvided {
                    self.consumeAliasAndReplace()
                }
            }
        }
    }
    
    public func autofillUserScriptDidRequestRefreshAlias(_: AutofillUserScript) {
        self.consumeAliasAndReplace()
    }
    
    public func autofillUserScript(_ : AutofillUserScript, didRequestStoreToken token: String, username: String, cohort: String?) {
        storeToken(token, username: username, cohort: cohort)
        NotificationCenter.default.post(name: .emailDidSignIn, object: self)
    }
}


extension EmailManager: TopAutofillEmailDelegate {

    public func topAutofillUserScriptDidRequestSignedInStatus(_: TopAutofillUserScript) -> Bool {
         return isSignedIn
    }

    public func topAutofillUserScriptDidRequestUsernameAndAlias(_: TopAutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion) {
        getAliasIfNeeded { [weak self] alias, error in
            guard let alias = alias, error == nil, let self = self else {
                completionHandler(nil, nil, error)
                return
            }

            completionHandler(self.username, alias, nil)
        }
    }
    
    public func topAutofillUserScript(_: TopAutofillUserScript,
                                   didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                                   shouldConsumeAliasIfProvided: Bool,
                                   completionHandler: @escaping AliasCompletion) {
            
        getAliasIfNeeded { [weak self] newAlias, error in
            guard let newAlias = newAlias, error == nil, let self = self else {
                completionHandler(nil, error)
                return
            }
            
            if requiresUserPermission {
                guard let delegate = self.aliasPermissionDelegate else {
                    assertionFailure("EmailUserScript requires permission to provide Alias")
                    completionHandler(nil, .permissionDelegateNil)
                    return
                }
                
                delegate.emailManager(self, didRequestPermissionToProvideAliasWithCompletion: { [weak self] permissionType in
                    switch permissionType {
                    case .user:
                        if let username = self?.username {
                            completionHandler(username, nil)
                        } else {
                            completionHandler(nil, .userRefused)
                        }
                    case .generated:
                        completionHandler(newAlias, nil)
                        if shouldConsumeAliasIfProvided {
                            self?.consumeAliasAndReplace()
                        }
                    case .none:
                        completionHandler(nil, .userRefused)
                    }
                })
            } else {
                completionHandler(newAlias, nil)
                if shouldConsumeAliasIfProvided {
                    self.consumeAliasAndReplace()
                }
            }
        }
    }
    
    public func topAutofillUserScriptDidRequestRefreshAlias(_: TopAutofillUserScript) {
        self.consumeAliasAndReplace()
    }
    
    public func topAutofillUserScript(_ : TopAutofillUserScript, didRequestStoreToken token: String, username: String, cohort: String?) {
        storeToken(token, username: username, cohort: cohort)
        NotificationCenter.default.post(name: .emailDidSignIn, object: self)
    }
}

// MARK: - Token Management

private extension EmailManager {
    func storeToken(_ token: String, username: String, cohort: String?) {
        storage.store(token: token, username: username, cohort: cohort)
        fetchAndStoreAlias()
    }
}

// MARK: - Alias Management

private extension EmailManager {
    
    struct EmailAliasResponse: Decodable {
        let address: String
    }
    
    typealias HTTPHeaders = [String: String]
    
    var emailHeaders: HTTPHeaders {
        guard let token = token else {
            return [:]
        }
        return ["Authorization": "Bearer " + token]
    }
    
    func consumeAliasAndReplace() {
        storage.deleteAlias()
        fetchAndStoreAlias()
    }
    
    func getAliasIfNeeded(timeoutInterval: TimeInterval = 4.0, completionHandler: @escaping AliasCompletion) {
        if let alias = alias {
            completionHandler(alias, nil)
            return
        }
        fetchAndStoreAlias(timeoutInterval: timeoutInterval) { newAlias, error in
            guard let newAlias = newAlias, error == nil  else {
                completionHandler(nil, error)
                return
            }
            completionHandler(newAlias, nil)
        }
    }

    func fetchAndStoreAlias(timeoutInterval: TimeInterval = 60.0, completionHandler: AliasCompletion? = nil) {
        fetchAlias(timeoutInterval: timeoutInterval) { [weak self] alias, error in
            guard let alias = alias, error == nil else {
                completionHandler?(nil, error)
                return
            }
            // Check we haven't signed out whilst waiting
            // if so we don't want to save sensitive data
            guard let self = self, self.isSignedIn else {
                completionHandler?(nil, .signedOut)
                return
            }
            self.storage.store(alias: alias)
            completionHandler?(alias, nil)
        }
    }

    func fetchAlias(timeoutInterval: TimeInterval = 60.0, completionHandler: AliasCompletion? = nil) {
        guard isSignedIn else {
            completionHandler?(nil, .signedOut)
            return
        }
        
        requestDelegate?.emailManager(self,
                                      requested: aliasAPIURL,
                                      method: "POST",
                                      headers: emailHeaders,
                                      parameters: [:],
                                      httpBody: nil,
                                      timeoutInterval: timeoutInterval) { data, error in
            guard let data = data, error == nil else {
                completionHandler?(nil, .noDataError)
                return
            }
            do {
                let decoder = JSONDecoder()
                let alias = try decoder.decode(EmailAliasResponse.self, from: data).address
                NotificationCenter.default.post(name: .emailDidGenerateAlias, object: self)
                completionHandler?(alias, nil)
            } catch {
                completionHandler?(nil, .invalidResponse)
            }
        }
    }

}

// MARK: - Waitlist Management

extension EmailManager {

    public typealias WaitlistRequestCompletion<T> = (Result<T, WaitlistRequestError>) -> Void

    public typealias JoinWaitlistCompletion = WaitlistRequestCompletion<WaitlistResponse>
    public typealias FetchInviteCodeCompletion = WaitlistRequestCompletion<EmailInviteCodeResponse>
    private typealias FetchWaitlistStatusCompletion = WaitlistRequestCompletion<WaitlistStatusResponse>

    public struct WaitlistResponse: Decodable {
        let token: String
        let timestamp: Int
    }

    struct WaitlistStatusResponse: Decodable {
        let timestamp: Int
    }

    public struct EmailInviteCodeResponse: Decodable {
        let code: String
    }

    public enum WaitlistRequestError: Error {
        case noDataError
        case invalidResponse
        case codeAlreadyExists
        case noCodeAvailable
        case notOnWaitlist
    }

    public func joinWaitlist(timeoutInterval: TimeInterval = 60.0, completionHandler: JoinWaitlistCompletion? = nil) {
        requestDelegate?.emailManager(self,
                                      requested: emailUrls.joinWaitlistAPI,
                                      method: "POST",
                                      headers: emailHeaders,
                                      parameters: nil,
                                      httpBody: nil,
                                      timeoutInterval: timeoutInterval) { [weak self] data, error in
            guard let self = self else { return }

            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completionHandler?(.failure(.noDataError))
                }

                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(WaitlistResponse.self, from: data)

                self.storage.store(waitlistToken: response.token)
                self.storage.store(waitlistTimestamp: response.timestamp)

                DispatchQueue.main.async {
                    completionHandler?(.success(response))
                }
            } catch {
                DispatchQueue.main.async {
                    completionHandler?(.failure(.noDataError))
                }
            }
        }
    }

    /// Fetches the invite code for users who have joined the waitlist. There are two steps required:
    ///
    /// 1. Query the waitlist status API to determine the status of the queue, which returns a timestamp
    /// 2. Compare the waitlist status timestamp against the locally persisted value, and status timestamp > local timestamp, then fetch the waitlist code using the saved token
    public func fetchInviteCodeIfAvailable(timeoutInterval: TimeInterval = 60.0, completionHandler: FetchInviteCodeCompletion? = nil) {
        guard storage.getWaitlistInviteCode() == nil else {
            completionHandler?(.failure(.codeAlreadyExists))
            return
        }

        // Verify that the waitlist has already been joined before checking the status.
        guard storage.getWaitlistToken() != nil, let storedTimestamp = storage.getWaitlistTimestamp() else {
            completionHandler?(.failure(.notOnWaitlist))
            return
        }

        fetchWaitlistStatus(timeoutInterval: timeoutInterval) { waitlistResult in
            switch waitlistResult {
            case .success(let statusResponse):
                if statusResponse.timestamp >= storedTimestamp {
                    self.fetchInviteCode(timeoutInterval: timeoutInterval, completionHandler: completionHandler)
                } else {
                    // If the user is still in the waitlist, no code is available.
                    completionHandler?(.failure(.noCodeAvailable))
                }
            case .failure(let error):
                completionHandler?(.failure(error))
            }
        }
    }

    private func fetchWaitlistStatus(timeoutInterval: TimeInterval = 60.0, completionHandler: FetchWaitlistStatusCompletion? = nil) {
        guard storage.getWaitlistInviteCode() == nil else {
            completionHandler?(.failure(.codeAlreadyExists))
            return
        }

        // Verify that the waitlist has already been joined before checking the status.
        guard storage.getWaitlistToken() != nil, storage.getWaitlistTimestamp() != nil else {
            completionHandler?(.failure(.notOnWaitlist))
            return
        }

        requestDelegate?.emailManager(self,
                                      requested: emailUrls.waitlistStatusAPI,
                                      method: "GET",
                                      headers: emailHeaders,
                                      parameters: nil,
                                      httpBody: nil,
                                      timeoutInterval: timeoutInterval) { data, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completionHandler?(.failure(.noDataError))
                }

                return
            }

            do {
                let decoder = JSONDecoder()
                let waitlistStatus = try decoder.decode(WaitlistStatusResponse.self, from: data)

                DispatchQueue.main.async {
                    completionHandler?(.success(waitlistStatus))
                }
            } catch {
                DispatchQueue.main.async {
                    completionHandler?(.failure(.noDataError))
                }
            }
        }
    }

    private func fetchInviteCode(timeoutInterval: TimeInterval = 60.0, completionHandler: FetchInviteCodeCompletion? = nil) {
        guard storage.getWaitlistInviteCode() == nil else {
            completionHandler?(.failure(.codeAlreadyExists))
            return
        }

        // Verify that the waitlist has already been joined before checking the status.
        guard let token = storage.getWaitlistToken(), storage.getWaitlistTimestamp() != nil else {
            completionHandler?(.failure(.notOnWaitlist))
            return
        }

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        let componentData = components.query?.data(using: .utf8)

        requestDelegate?.emailManager(self,
                                      requested: emailUrls.getInviteCodeAPI,
                                      method: "POST",
                                      headers: emailHeaders,
                                      parameters: nil,
                                      httpBody: componentData,
                                      timeoutInterval: timeoutInterval) { [weak self] data, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completionHandler?(.failure(.noDataError))
                }

                return
            }

            do {
                let decoder = JSONDecoder()
                let inviteCodeResponse = try decoder.decode(EmailInviteCodeResponse.self, from: data)

                self?.storage.store(inviteCode: inviteCodeResponse.code)

                DispatchQueue.main.async {
                    completionHandler?(.success(inviteCodeResponse))
                }
            } catch {
                DispatchQueue.main.async {
                    completionHandler?(.failure(.noDataError))
                }
            }
        }
    }

}

// swiftlint:enable file_length
