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

public enum EmailKeychainAccessType: String {
    case getUsername
    case getToken
    case getAlias
    case getCohort
    case getLastUseData
    case storeTokenUsernameCohort
    case storeAlias
    case storeLastUseDate
    case deleteAuthenticationState
    case deleteAlias
}

public enum EmailKeychainAccessError: Error, Equatable {
    case failedToDecodeKeychainValueAsData
    case failedToDecodeKeychainDataAsString
    case failedToDecodeKeychainDataAsInt
    case keychainSaveFailure(OSStatus)
    case keychainDeleteFailure(OSStatus)
    case keychainLookupFailure(OSStatus)
    
    public var errorDescription: String {
        switch self {
        case .failedToDecodeKeychainValueAsData: return "failedToDecodeKeychainValueAsData"
        case .failedToDecodeKeychainDataAsString: return "failedToDecodeKeychainDataAsString"
        case .failedToDecodeKeychainDataAsInt: return "failedToDecodeKeychainDataAsInt"
        case .keychainSaveFailure: return "keychainSaveFailure"
        case .keychainDeleteFailure: return "keychainDeleteFailure"
        case .keychainLookupFailure: return "keychainLookupFailure"
        }
    }
}

public protocol EmailManagerStorage: AnyObject {
    func getUsername() throws -> String?
    func getToken() throws -> String?
    func getAlias() throws -> String?
    func getCohort() throws -> String?
    func getLastUseDate() throws -> String?
    func store(token: String, username: String, cohort: String?) throws
    func store(alias: String) throws
    func store(lastUseDate: String) throws
    func deleteAlias() throws
    func deleteAuthenticationState() throws
    func deleteWaitlistState() throws
}

public enum EmailManagerPermittedAddressType {
    case user
    case generated
    case none
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

    func emailManagerKeychainAccessFailed(accessType: EmailKeychainAccessType, error: EmailKeychainAccessError)
    
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
    }

    var emailAliasAPI: URL {
        return URL(string: Url.emailAlias)!
    }
    
    public init() { }
}

public typealias AliasCompletion = (String?, AliasRequestError?) -> Void
public typealias UsernameAndAliasCompletion = (_ username: String?, _ alias: String?, AliasRequestError?) -> Void
public typealias UserDataCompletion = (_ username: String?, _ alias: String?, _ token: String?, AliasRequestError?) -> Void

public class EmailManager {
    
    private static let emailDomain = "duck.com"
    
    private let storage: EmailManagerStorage
    public weak var aliasPermissionDelegate: EmailManagerAliasPermissionDelegate?
    public weak var requestDelegate: EmailManagerRequestDelegate?
    
    public enum NotificationParameter {
        public static let cohort = "cohort"
    }
    
    private lazy var emailUrls = EmailUrls()
    private lazy var aliasAPIURL = emailUrls.emailAliasAPI

    private var dateFormatter = ISO8601DateFormatter()
    
    private var username: String? {
        do {
            return try storage.getUsername()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(accessType: .getUsername, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
            
            return nil
        }
    }

    private var token: String? {
        do {
            return try storage.getToken()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(accessType: .getToken, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
            
            return nil
        }
    }

    private var alias: String? {
        do {
            return try storage.getAlias()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(accessType: .getAlias, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
            
            return nil
        }
    }

    public var cohort: String? {
        do {
            return try storage.getCohort()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(accessType: .getCohort, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
            
            return nil
        }
    }

    public var lastUseDate: String {
        do {
            return try storage.getLastUseDate() ?? ""
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(accessType: .getLastUseData, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
            
            return ""
        }
    }

    public func updateLastUseDate() {
        let dateString = dateFormatter.string(from: Date())
        
        do {
            try storage.store(lastUseDate: dateString)
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(accessType: .storeLastUseDate, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
        }
    }

    public var isSignedIn: Bool {
        return token != nil && username != nil
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
        // Retrieve the cohort before it gets removed from storage, so that it can be passed as a notification parameter.
        let currentCohortValue = try? storage.getCohort()

        do {
            try storage.deleteAuthenticationState()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                self.requestDelegate?.emailManagerKeychainAccessFailed(accessType: .deleteAuthenticationState, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
        }
        
        var notificationParameters: [String: String] = [:]
        
        if let currentCohortValue = currentCohortValue {
            notificationParameters[NotificationParameter.cohort] = currentCohortValue
        }

        NotificationCenter.default.post(name: .emailDidSignOut, object: self, userInfo: notificationParameters)
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

    public func autofillUserScriptDidRequestUserData(_: AutofillUserScript, completionHandler: @escaping UserDataCompletion) {
        getAliasIfNeeded { [weak self] alias, error in
            guard let alias = alias, error == nil, let self = self else {
                completionHandler(nil, nil, nil, error)
                return
            }

            completionHandler(self.username, alias, self.token, nil)
        }
    }

    public func autofillUserScriptDidRequestSignOut(_: AutofillUserScript) {
        self.signOut()
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
        
        var notificationParameters: [String: String] = [:]
        
        if let cohort = cohort {
            notificationParameters[NotificationParameter.cohort] = cohort
        }

        NotificationCenter.default.post(name: .emailDidSignIn, object: self, userInfo: notificationParameters)
    }
}

// MARK: - Token Management

private extension EmailManager {
    func storeToken(_ token: String, username: String, cohort: String?) {
        do {
            try storage.store(token: token, username: username, cohort: cohort)
        } catch {
            if let error = error as? EmailKeychainAccessError {
                requestDelegate?.emailManagerKeychainAccessFailed(accessType: .storeTokenUsernameCohort, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
        }

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
        do {
            try storage.deleteAlias()
        } catch {
            if let error = error as? EmailKeychainAccessError {
                self.requestDelegate?.emailManagerKeychainAccessFailed(accessType: .deleteAlias, error: error)
            } else {
                assertionFailure("Expected EmailKeychainAccessFailure")
            }
        }

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
            
            do {
                try self.storage.store(alias: alias)
            } catch {
                if let error = error as? EmailKeychainAccessError {
                    self.requestDelegate?.emailManagerKeychainAccessFailed(accessType: .storeAlias, error: error)
                } else {
                    assertionFailure("Expected EmailKeychainAccessFailure")
                }
            }

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

// swiftlint:enable file_length
