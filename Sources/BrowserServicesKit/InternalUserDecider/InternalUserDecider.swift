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

public protocol InternalUserDecider {
    
    var isInternalUser: Bool { get }
    
    @discardableResult
    func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool
}

public protocol InternalUserStore {
    var didVerifyInternalUser: Bool { get set }
}

public class DefaultInternalUserDecider: InternalUserDecider {
    private let userDefaults = UserDefaults()
    private static let didVerifyInternalUserKey = "com.duckduckgo.browserServicesKit.featureFlaggingDidVerifyInternalUser"
    private static let internalUserVerificationURLHost = "use-login.duckduckgo.com"
    
    public init() {
    }

    public var isInternalUser: Bool {
        return didVerifyInternalUser
    }

    private var didVerifyInternalUser: Bool {
        get {
            return userDefaults.bool(forKey: Self.didVerifyInternalUserKey)
        }
        set {
            userDefaults.set(newValue, forKey: Self.didVerifyInternalUserKey)
        }
    }

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
