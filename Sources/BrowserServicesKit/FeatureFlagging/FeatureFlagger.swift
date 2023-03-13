//
//  FeatureFlagger.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public enum Feature: String {
    case debugMenu
    case autofill
}

public protocol FeatureFlagger {
    func isFeatureOn(_ feature: Feature) -> Bool
}

public protocol InternalUserDecider {
    
    var isInternalUser: Bool { get }
    
    @discardableResult
    func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool
}

public protocol InternalUserStore {
    var didVerifyInternalUser: Bool { get set }
}

public class DefaultInternalUserDecider: FeatureFlagger {
    private let userDefaults = UserDefaults()
    
    public init() {
    }
    
    public func isFeatureOn(_ feature: Feature) -> Bool {
        switch feature {
        case .debugMenu:
            return isInternalUser
        case .autofill:
            if isInternalUser {
                return true
            } else {
                return false
            }
        }
    }

    private static let didVerifyInternalUserKey = "com.duckduckgo.browserServicesKit.featureFlaggingDidVerifyInternalUser"
    private var didVerifyInternalUser: Bool {
        get {
            return userDefaults.bool(forKey: Self.didVerifyInternalUserKey)
        }
        set {
            userDefaults.set(newValue, forKey: Self.didVerifyInternalUserKey)
        }
    }
}

extension DefaultInternalUserDecider: InternalUserDecider {
    
    public var isInternalUser: Bool {
        return didVerifyInternalUser
    }
    
    private static let internalUserVerificationURLHost = "use-login.duckduckgo.com"
    
    @discardableResult
    public func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool {
        if isInternalUser { // If we're already an internal user, we don't need to do anything
            return false
        }
        
        if shouldMarkUserAsInternal(forUrl: url, statusCode: response?.statusCode) {
            didVerifyInternalUser = true
            return true
        }
        return false
    }
    
    func shouldMarkUserAsInternal(forUrl url: URL?, statusCode: Int?) -> Bool {
        if let statusCode = statusCode,
           statusCode == 200,
           let url = url,
           url.host == DefaultInternalUserDecider.internalUserVerificationURLHost {
            
            return true
        }
        return false
    }
}
